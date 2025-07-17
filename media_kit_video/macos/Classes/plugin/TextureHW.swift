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
    NSLog("[media_kit][TextureHW] Initializing TextureHW...")
    
    self.handle = handle
    self.updateCallback = updateCallback
    
    NSLog("[media_kit][TextureHW] Creating OpenGL pixel format...")
    self.pixelFormat = OpenGLHelpers.createPixelFormat()
    
    NSLog("[media_kit][TextureHW] Creating OpenGL context...")
    self.context = OpenGLHelpers.createContext(pixelFormat)
    
    NSLog("[media_kit][TextureHW] Creating texture cache...")
    self.textureCache = OpenGLHelpers.createTextureCache(context, pixelFormat)

    super.init()

    NSLog("[media_kit][TextureHW] Initializing MPV...")
    self.initMPV()
    
    NSLog("[media_kit][TextureHW] TextureHW initialization completed")
  }

  deinit {
    NSLog("[media_kit][TextureHW] Destroying TextureHW...")
    disposePixelBuffer()
    disposeMPV()
    OpenGLHelpers.deleteTextureCache(textureCache)
    OpenGLHelpers.deletePixelFormat(pixelFormat)

    // Deleting the context may cause potential RAM or VRAM memory leaks, as it
    // is used in the `deinit` method of the `TextureGLContext`.
    // Potential fix: use a counter, and delete it only when the counter reaches
    // zero
    OpenGLHelpers.deleteContext(context)
    NSLog("[media_kit][TextureHW] TextureHW destroyed")
  }

  public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    let textureContext = textureContexts.current
    if textureContext == nil {
      NSLog("[media_kit][TextureHW] ⚠️ No current texture context for copyPixelBuffer")
      return nil
    }

    if TextureHW.frameCount % 20 == 0 {
      NSLog("[media_kit][TextureHW] Copying pixel buffer: FBO=\(textureContext!.frameBuffer)")
    }
    return Unmanaged.passRetained(textureContext!.pixelBuffer)
  }

  private func initMPV() {
    NSLog("[media_kit][TextureHW] Initializing MPV render context...")
    
    CGLSetCurrentContext(context)
    defer {
      OpenGLHelpers.checkError("initMPV")
      CGLSetCurrentContext(nil)
    }

    let api = UnsafeMutableRawPointer(
      mutating: (MPV_RENDER_API_TYPE_OPENGL as NSString).utf8String
    )
    NSLog("[media_kit][TextureHW] Using MPV render API: \(MPV_RENDER_API_TYPE_OPENGL)")
    
    var procAddress = mpv_opengl_init_params(
      get_proc_address: {
        (ctx, name) in
        return TextureHW.getProcAddress(ctx, name)
      },
      get_proc_address_ctx: nil
    )
    NSLog("[media_kit][TextureHW] OpenGL init params created")

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
    NSLog("[media_kit][TextureHW] MPV render params prepared")

    NSLog("[media_kit][TextureHW] Creating MPV render context...")
    let createResult = mpv_render_context_create(&renderContext, handle, &params)
    NSLog("[media_kit][TextureHW] mpv_render_context_create result: \(createResult)")
    
    MPVHelpers.checkError(createResult)
    
    if renderContext != nil {
      NSLog("[media_kit][TextureHW] ✅ MPV render context created successfully")
    } else {
      NSLog("[media_kit][TextureHW] ⚠️ MPV render context is nil!")
    }

    NSLog("[media_kit][TextureHW] Setting MPV render update callback...")
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
    NSLog("[media_kit][TextureHW] MPV render update callback set")
    
    NSLog("[media_kit][TextureHW] MPV initialization completed")
  }

  private func disposeMPV() {
    NSLog("[media_kit][TextureHW] Disposing MPV render context...")
    CGLSetCurrentContext(context)
    defer {
      OpenGLHelpers.checkError("disposeMPV")
      CGLSetCurrentContext(nil)
    }

    mpv_render_context_set_update_callback(renderContext, nil, nil)
    mpv_render_context_free(renderContext)
    NSLog("[media_kit][TextureHW] MPV render context disposed")
  }

  public func resize(_ size: CGSize) {
    if size.width == 0 || size.height == 0 {
      NSLog("[media_kit][TextureHW] ⚠️ Invalid resize size: \(size.width)x\(size.height)")
      return
    }

    NSLog("[media_kit][TextureHW] Resizing to: \(size.width)x\(size.height)")
    createPixelBuffer(size)
    NSLog("[media_kit][TextureHW] Resize completed")
  }

  private func createPixelBuffer(_ size: CGSize) {
    NSLog("[media_kit][TextureHW] Creating pixel buffers for size: \(size.width)x\(size.height)")
    disposePixelBuffer()

    NSLog("[media_kit][TextureHW] Creating 3 TextureGLContext instances...")
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
    NSLog("[media_kit][TextureHW] Pixel buffers created successfully")
  }

  private func disposePixelBuffer() {
    NSLog("[media_kit][TextureHW] Disposing pixel buffers...")
    textureContexts.reinit(objects: [], skipCheckArgs: true)
    NSLog("[media_kit][TextureHW] Pixel buffers disposed")
  }

  public func render(_ size: CGSize) {
    let textureContext = textureContexts.nextAvailable()
    if textureContext == nil {
      NSLog("[media_kit][TextureHW] ⚠️ No available texture context!")
      return
    }

    if TextureHW.frameCount % 20 == 0 {
      NSLog("[media_kit][TextureHW] Got texture context: FBO=\(textureContext!.frameBuffer), texture=\(CVOpenGLTextureGetName(textureContext!.texture))")
    }

    CGLSetCurrentContext(context)
    defer {
      OpenGLHelpers.checkError("render")
      CGLSetCurrentContext(nil)
    }

    // 增加帧计数器
    TextureHW.frameCount += 1
    let shouldLogDetailed = TextureHW.frameCount % 20 == 0

    glBindFramebuffer(GLenum(GL_FRAMEBUFFER), textureContext!.frameBuffer)
    
    if shouldLogDetailed {
      NSLog("[media_kit][TextureHW] ===== Frame \(TextureHW.frameCount) Detailed Log =====")
      NSLog("[media_kit][TextureHW] Using frameBuffer: \(textureContext!.frameBuffer)")
      
      let texName = CVOpenGLTextureGetName(textureContext!.texture)
      NSLog("[media_kit][TextureHW] CVOpenGLTexture name: \(texName)")
      
      // 检查纹理类型
      let textureTarget = CVOpenGLTextureGetTarget(textureContext!.texture)
      NSLog("[media_kit][TextureHW] Texture target: \(textureTarget)")
      
      // 检查纹理格式
      var internalFormat = GLint(0)
      var format = GLint(0)
      var type = GLint(0)
      var width = GLint(0)
      var height = GLint(0)
      
      glBindTexture(GLenum(textureTarget), texName)
      glGetTexLevelParameteriv(GLenum(textureTarget), 0, GLenum(GL_TEXTURE_INTERNAL_FORMAT), &internalFormat)
      glGetTexLevelParameteriv(GLenum(textureTarget), 0, GLenum(GL_TEXTURE_RED_TYPE), &type)
      glGetTexLevelParameteriv(GLenum(textureTarget), 0, GLenum(GL_TEXTURE_WIDTH), &width)
      glGetTexLevelParameteriv(GLenum(textureTarget), 0, GLenum(GL_TEXTURE_HEIGHT), &height)
      glBindTexture(GLenum(textureTarget), 0)
      
      NSLog("[media_kit][TextureHW] Texture format: internal=\(internalFormat), type=\(type), size=\(width)x\(height)")
      
      // 检查当前绑定的FBO
      var currentFBO = GLint(0)
      glGetIntegerv(GLenum(GL_FRAMEBUFFER_BINDING), &currentFBO)
      NSLog("[media_kit][TextureHW] Current bound FBO: \(currentFBO)")
    }
    
    defer {
      glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
    }

    // 检查 FBO 完整性
    let fboStatus = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
    if shouldLogDetailed {
      NSLog("[media_kit][TextureHW] glCheckFramebufferStatus: \(fboStatus)")
      if fboStatus != GLenum(GL_FRAMEBUFFER_COMPLETE) {
        NSLog("[media_kit][TextureHW] ⚠️ FBO is not complete! Status: \(fboStatus)")
      }
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

    if shouldLogDetailed {
      NSLog("[media_kit][TextureHW] MPV FBO params: fbo=\(fbo.fbo), w=\(fbo.w), h=\(fbo.h), internal_format=\(fbo.internal_format)")
    }

    var params: [mpv_render_param] = [
      mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: fboPtr),
      mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
    ]
    let mpvRenderResult = mpv_render_context_render(renderContext, &params)
    
    if shouldLogDetailed {
      NSLog("[media_kit][TextureHW] mpv_render_context_render result: \(mpvRenderResult)")
      if mpvRenderResult != 0 {
        NSLog("[media_kit][TextureHW] ⚠️ MPV render failed with error: \(mpvRenderResult)")
      }
    }

    // 打印 glGetError
    let glErr = glGetError()
    if glErr != GLenum(GL_NO_ERROR) {
      NSLog("[media_kit][TextureHW] ⚠️ glGetError: \(glErr)")
    }

    // 每20帧 dump 一次 FBO 内容为 PNG 到临时目录
    if shouldLogDetailed {
      // 检查 FBO 绑定的纹理格式
      var attachment = GLint(0)
      glGetFramebufferAttachmentParameteriv(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE), &attachment)
      NSLog("[media_kit][TextureHW] FBO attachment type: \(attachment)")
      
      if attachment == GL_FRAMEBUFFER_DEFAULT {
        NSLog("[media_kit][TextureHW] ⚠️ Using default framebuffer - this might be the issue!")
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
        NSLog("[media_kit][TextureHW] FBO texture internal format: \(internalFormat), type: \(type)")
        glBindTexture(GLenum(GL_TEXTURE_2D), 0)
      }
      
      // 检查视口设置
      var viewport = [GLint](repeating: 0, count: 4)
      glGetIntegerv(GLenum(GL_VIEWPORT), &viewport)
      NSLog("[media_kit][TextureHW] Viewport: \(viewport)")
      
      // 检查当前OpenGL状态
      var blendEnabled = GLboolean(0)
      glGetBooleanv(GLenum(GL_BLEND), &blendEnabled)
      NSLog("[media_kit][TextureHW] GL_BLEND enabled: \(blendEnabled)")
      
      var depthTestEnabled = GLboolean(0)
      glGetBooleanv(GLenum(GL_DEPTH_TEST), &depthTestEnabled)
      NSLog("[media_kit][TextureHW] GL_DEPTH_TEST enabled: \(depthTestEnabled)")
      
      // Dump FBO内容
      let width = Int(size.width)
      let height = Int(size.height)
      var pixels = [UInt8](repeating: 0, count: width * height * 4)
      glReadPixels(0, 0, GLsizei(width), GLsizei(height), GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), &pixels)
      
      // 检查像素数据是否全黑
      let nonZeroPixels = pixels.filter { $0 > 0 }.count
      NSLog("[media_kit][TextureHW] Non-zero pixels: \(nonZeroPixels)/\(pixels.count) (\(Float(nonZeroPixels) / Float(pixels.count) * 100)%)")
      
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
      
      NSLog("[media_kit][TextureHW] ===== End Frame \(TextureHW.frameCount) =====")
    } else {
      // 简化的帧信息
      NSLog("[media_kit][TextureHW] Frame \(TextureHW.frameCount): FBO=\(textureContext!.frameBuffer), MPV=\(mpvRenderResult), GL=\(glErr)")
    }

    glFlush()

    if shouldLogDetailed {
      NSLog("[media_kit][TextureHW] Pushing texture context back to pool: FBO=\(textureContext!.frameBuffer)")
    }
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
      NSLog("[media_kit][TextureHW] ⚠️ Cannot get OpenGL function pointer for: \(String(cString: name!))")
    } else {
      NSLog("[media_kit][TextureHW] ✅ Got OpenGL function pointer for: \(String(cString: name!))")
    }
    return addr
  }
}
