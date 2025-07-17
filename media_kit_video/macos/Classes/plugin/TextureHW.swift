import FlutterMacOS
import OpenGL.GL
import OpenGL.GL3

public class TextureHW: NSObject, FlutterTexture, ResizableTextureProtocol {
  public typealias UpdateCallback = () -> Void

  // 新增：静态变量，记录总帧数
  static var frameCount = 0

  private let handle: OpaquePointer
  private let updateCallback: UpdateCallback
  private let pixelFormat: CGLPixelFormatObj
  private let context: CGLContextObj
  private let textureCache: CVOpenGLTextureCache
  private var renderContext: OpaquePointer?
  private var textureContexts = SwappableObjectManager<TextureGLContext>(
    objects: [],
    skipCheckArgs: true
  )

  init(
    handle: OpaquePointer,
    updateCallback: @escaping UpdateCallback
  ) {
    self.handle = handle
    self.updateCallback = updateCallback
    self.pixelFormat = OpenGLHelpers.createPixelFormat()
    self.context = OpenGLHelpers.createContext(pixelFormat)
    self.textureCache = OpenGLHelpers.createTextureCache(context, pixelFormat)

    super.init()

    self.initMPV()
  }

  deinit {
    disposePixelBuffer()
    disposeMPV()
    OpenGLHelpers.deleteTextureCache(textureCache)
    OpenGLHelpers.deletePixelFormat(pixelFormat)

    // Deleting the context may cause potential RAM or VRAM memory leaks, as it
    // is used in the `deinit` method of the `TextureGLContext`.
    // Potential fix: use a counter, and delete it only when the counter reaches
    // zero
    OpenGLHelpers.deleteContext(context)
  }

  public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    let textureContext = textureContexts.current
    if textureContext == nil {
      return nil
    }

    return Unmanaged.passRetained(textureContext!.pixelBuffer)
  }

  private func initMPV() {
    CGLSetCurrentContext(context)
    defer {
      OpenGLHelpers.checkError("initMPV")
      CGLSetCurrentContext(nil)
    }

    let api = UnsafeMutableRawPointer(
      mutating: (MPV_RENDER_API_TYPE_OPENGL as NSString).utf8String
    )
    var procAddress = mpv_opengl_init_params(
      get_proc_address: {
        (ctx, name) in
        return TextureHW.getProcAddress(ctx, name)
      },
      get_proc_address_ctx: nil
    )

    var params: [mpv_render_param] = withUnsafeMutableBytes(of: &procAddress) {
      procAddress in
      return [
        mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: api),
        mpv_render_param(
          type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS,
          data: procAddress.baseAddress.map {
            UnsafeMutableRawPointer($0)
          }
        ),
        mpv_render_param(),
      ]
    }

    MPVHelpers.checkError(
      mpv_render_context_create(&renderContext, handle, &params)
    )

    mpv_render_context_set_update_callback(
      renderContext,
      { (ctx) in
        let that = unsafeBitCast(ctx, to: TextureHW.self)
        DispatchQueue.main.async {
          that.updateCallback()
        }
      },
      UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    )
  }

  private func disposeMPV() {
    CGLSetCurrentContext(context)
    defer {
      OpenGLHelpers.checkError("disposeMPV")
      CGLSetCurrentContext(nil)
    }

    mpv_render_context_set_update_callback(renderContext, nil, nil)
    mpv_render_context_free(renderContext)
  }

  public func resize(_ size: CGSize) {
    if size.width == 0 || size.height == 0 {
      return
    }

    NSLog("TextureGL: resize: \(size.width)x\(size.height)")
    createPixelBuffer(size)
  }

  private func createPixelBuffer(_ size: CGSize) {
    disposePixelBuffer()

    textureContexts.reinit(
      objects: [
        TextureGLContext(
          context: context,
          textureCache: textureCache,
          size: size
        ),
        TextureGLContext(
          context: context,
          textureCache: textureCache,
          size: size
        ),
        TextureGLContext(
          context: context,
          textureCache: textureCache,
          size: size
        ),
      ],
      skipCheckArgs: true
    )
  }

  private func disposePixelBuffer() {
    textureContexts.reinit(objects: [], skipCheckArgs: true)
  }

  public func render(_ size: CGSize) {
    let textureContext = textureContexts.nextAvailable()
    if textureContext == nil {
      return
    }

    CGLSetCurrentContext(context)
    defer {
      OpenGLHelpers.checkError("render")
      CGLSetCurrentContext(nil)
    }

    glBindFramebuffer(GLenum(GL_FRAMEBUFFER), textureContext!.frameBuffer)
    NSLog("[media_kit][TextureHW] Using frameBuffer: \(textureContext!.frameBuffer)")
    let texName = CVOpenGLTextureGetName(textureContext!.texture)
    NSLog("[media_kit][TextureHW] CVOpenGLTexture name: \(texName)")
    defer {
      glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
    }

    // 检查 FBO 完整性
    let fboStatus = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
    NSLog("[media_kit][TextureHW] glCheckFramebufferStatus: \(fboStatus)")
    if fboStatus != GLenum(GL_FRAMEBUFFER_COMPLETE) {
      NSLog("[media_kit][TextureHW] FBO is not complete!")
    }

    // 确保启用混合模式，正确叠加字幕 bitmap
    glEnable(GLenum(GL_BLEND))
    glBlendFunc(GLenum(GL_SRC_ALPHA), GLenum(GL_ONE_MINUS_SRC_ALPHA))

    var fbo = mpv_opengl_fbo(
      fbo: Int32(textureContext!.frameBuffer),
      w: Int32(size.width),
      h: Int32(size.height),
      internal_format: 0
    )
    let fboPtr = withUnsafeMutablePointer(to: &fbo) { $0 }

    var params: [mpv_render_param] = [
      mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: fboPtr),
      mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
    ]
    let mpvRenderResult = mpv_render_context_render(renderContext, &params)
    NSLog("[media_kit][TextureHW] mpv_render_context_render result: \(mpvRenderResult)")

    // 打印 glGetError
    let glErr = glGetError()
    if glErr != GLenum(GL_NO_ERROR) {
      NSLog("[media_kit][TextureHW] glGetError: \(glErr)")
    }

    // 新增：每20帧 dump 一次 FBO 内容为 PNG 到桌面
    TextureHW.frameCount += 1
    if TextureHW.frameCount % 20 == 0 {
      // 检查 FBO 绑定的纹理格式
      var attachment = GLint(0)
      glGetFramebufferAttachmentParameteriv(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE), &attachment)
      NSLog("[media_kit][TextureHW] FBO attachment type: \(attachment)")
      
      if attachment == GL_FRAMEBUFFER_DEFAULT {
        NSLog("[media_kit][TextureHW] Using default framebuffer")
      } else if attachment == GL_TEXTURE {
        var textureId = GLint(0)
        glGetFramebufferAttachmentParameteriv(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME), &textureId)
        NSLog("[media_kit][TextureHW] FBO bound to texture: \(textureId)")
        
        // 检查纹理格式
        glBindTexture(GLenum(GL_TEXTURE_2D), GLuint(textureId))
        var internalFormat = GLint(0)
        var format = GLint(0)
        var type = GLint(0)
        glGetTexLevelParameteriv(GLenum(GL_TEXTURE_2D), 0, GLenum(GL_TEXTURE_INTERNAL_FORMAT), &internalFormat)
        glGetTexLevelParameteriv(GLenum(GL_TEXTURE_2D), 0, GLenum(GL_TEXTURE_RED_TYPE), &type)
        NSLog("[media_kit][TextureHW] Texture internal format: \(internalFormat), type: \(type)")
        glBindTexture(GLenum(GL_TEXTURE_2D), 0)
      }
      
      let width = Int(size.width)
      let height = Int(size.height)
      var pixels = [UInt8](repeating: 0, count: width * height * 4)
      glReadPixels(0, 0, GLsizei(width), GLsizei(height), GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), &pixels)
      let colorSpace = CGColorSpaceCreateDeviceRGB()
      let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
      let provider = CGDataProvider(data: NSData(bytes: &pixels, length: pixels.count * MemoryLayout<UInt8>.size))
      if let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo, provider: provider!, decode: nil, shouldInterpolate: false, intent: .defaultIntent) {
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
        // 保存到临时目录
        let tempDir = FileManager.default.temporaryDirectory
        let dest = tempDir.appendingPathComponent("fbo_dump_\(TextureHW.frameCount).png")
        if let tiff = nsImage.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
          try? png.write(to: dest)
          NSLog("[media_kit][TextureHW] FBO dump saved to \(dest.path)")
        }
      }
    }

    glFlush()

    textureContexts.pushAsReady(textureContext!)
  }

  static private func getProcAddress(
    _ ctx: UnsafeMutableRawPointer?,
    _ name: UnsafePointer<Int8>?
  ) -> UnsafeMutableRawPointer? {
    let symbol: CFString = CFStringCreateWithCString(
      kCFAllocatorDefault,
      name,
      kCFStringEncodingASCII
    )
    let indentifier = CFBundleGetBundleWithIdentifier(
      "com.apple.opengl" as CFString
    )
    let addr = CFBundleGetFunctionPointerForName(indentifier, symbol)

    if addr == nil {
      NSLog("Cannot get OpenGL function pointer!")
    }
    return addr
  }
}
