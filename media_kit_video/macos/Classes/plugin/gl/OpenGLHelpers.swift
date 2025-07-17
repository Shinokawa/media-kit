import Cocoa
import OpenGL.GL
import OpenGL.GL3

public class OpenGLHelpers {
  static public func createPixelFormat() -> CGLPixelFormatObj {
    NSLog("[media_kit][OpenGLHelpers] Creating OpenGL pixel format...")
    // from mpv
    let attributes: [CGLPixelFormatAttribute] = [
      kCGLPFAOpenGLProfile,
      CGLPixelFormatAttribute(kCGLOGLPVersion_3_2_Core.rawValue),
      kCGLPFAAccelerated,
      kCGLPFADoubleBuffer,
      kCGLPFAColorSize, _CGLPixelFormatAttribute(rawValue: 64),
      kCGLPFAColorFloat,
      kCGLPFABackingStore,
      kCGLPFAAllowOfflineRenderers,
      kCGLPFASupportsAutomaticGraphicsSwitching,
      _CGLPixelFormatAttribute(rawValue: 0),
    ]

    var npix: GLint = 0
    var pixelFormat: CGLPixelFormatObj?
    CGLChoosePixelFormat(attributes, &pixelFormat, &npix)
    
    NSLog("[media_kit][OpenGLHelpers] Pixel format created: \(pixelFormat!)")
    return pixelFormat!
  }

  static public func createContext(
    _ pixelFormat: CGLPixelFormatObj
  ) -> CGLContextObj {
    NSLog("[media_kit][OpenGLHelpers] Creating OpenGL context...")
    var context: CGLContextObj?
    let error = CGLCreateContext(pixelFormat, nil, &context)
    if error != kCGLNoError {
      let errS = String(cString: CGLErrorString(error))
      NSLog("[media_kit][OpenGLHelpers] ⚠️ Failed to create context: \(errS)")
      exit(1)
    }

    NSLog("[media_kit][OpenGLHelpers] OpenGL context created: \(context!)")
    return context!
  }

  static public func createTextureCache(
    _ context: CGLContextObj,
    _ pixelFormat: CGLPixelFormatObj
  ) -> CVOpenGLTextureCache {
    NSLog("[media_kit][OpenGLHelpers] Creating texture cache...")
    var textureCache: CVOpenGLTextureCache?

    let cvret: CVReturn = CVOpenGLTextureCacheCreate(
      kCFAllocatorDefault,
      nil,
      context,
      pixelFormat,
      nil,
      &textureCache
    )
    assert(cvret == kCVReturnSuccess, "CVOpenGLTextureCacheCreate")
    
    NSLog("[media_kit][OpenGLHelpers] Texture cache created: \(textureCache!)")
    return textureCache!
  }

  static public func createPixelBuffer(_ size: CGSize) -> CVPixelBuffer {
    NSLog("[media_kit][OpenGLHelpers] Creating pixel buffer for size: \(size.width)x\(size.height)")
    var pixelBuffer: CVPixelBuffer?

    let attrs =
      [
        kCVPixelBufferMetalCompatibilityKey: true
      ] as CFDictionary

    let cvret: CVReturn = CVPixelBufferCreate(
      kCFAllocatorDefault,
      Int(size.width),
      Int(size.height),
      kCVPixelFormatType_32BGRA,
      attrs,
      &pixelBuffer
    )
    assert(cvret == kCVReturnSuccess, "CVPixelBufferCreate")
    
    NSLog("[media_kit][OpenGLHelpers] Pixel buffer created: \(pixelBuffer!)")
    return pixelBuffer!
  }

  static public func createTexture(
    _ textureCache: CVOpenGLTextureCache,
    _ pixelBuffer: CVPixelBuffer
  ) -> CVOpenGLTexture {
    NSLog("[media_kit][OpenGLHelpers] Creating texture from pixel buffer...")
    var texture: CVOpenGLTexture?

    let cvret: CVReturn = CVOpenGLTextureCacheCreateTextureFromImage(
      kCFAllocatorDefault,
      textureCache,
      pixelBuffer,
      nil,
      &texture
    )
    assert(
      cvret == kCVReturnSuccess,
      "CVOpenGLTextureCacheCreateTextureFromImage"
    )
    
    NSLog("[media_kit][OpenGLHelpers] Texture created: \(texture!)")
    return texture!
  }

  static public func createRenderBuffer(
    _ context: CGLContextObj,
    _ size: CGSize
  ) -> GLuint {
    NSLog("[media_kit][OpenGLHelpers] Creating render buffer for size: \(size.width)x\(size.height)")
    CGLSetCurrentContext(context)
    defer {
      OpenGLHelpers.checkError("createRenderBuffer")
      CGLSetCurrentContext(nil)
    }

    var renderBuffer: GLuint = GLuint()
    glGenRenderbuffers(1, &renderBuffer)
    glBindRenderbuffer(GLenum(GL_RENDERBUFFER), renderBuffer)
    defer {
      glBindRenderbuffer(GLenum(GL_RENDERBUFFER), 0)
    }

    glRenderbufferStorage(
      GLenum(GL_RENDERBUFFER),
      GLenum(GL_DEPTH24_STENCIL8),
      GLsizei(size.width),
      GLsizei(size.height)
    )
    
    NSLog("[media_kit][OpenGLHelpers] Render buffer created: \(renderBuffer)")
    return renderBuffer
  }

  static public func createFrameBuffer(
    context: CGLContextObj,
    renderBuffer: GLuint,
    texture: CVOpenGLTexture,
    size: CGSize
  ) -> GLuint {
    CGLSetCurrentContext(context)
    defer {
      OpenGLHelpers.checkError("createFrameBuffer")
      CGLSetCurrentContext(nil)
    }

    NSLog("[media_kit][OpenGLHelpers] Creating FBO for size: \(size.width)x\(size.height)")
    
    let textureName: GLuint = CVOpenGLTextureGetName(texture)
    let textureTarget = CVOpenGLTextureGetTarget(texture)
    NSLog("[media_kit][OpenGLHelpers] Texture name: \(textureName), target: \(textureTarget)")
    
    glBindTexture(GLenum(textureTarget), textureName)
    defer {
      glBindTexture(GLenum(textureTarget), 0)
    }

    // 检查纹理格式
    var internalFormat = GLint(0)
    var type = GLint(0)
    var width = GLint(0)
    var height = GLint(0)
    
    glGetTexLevelParameteriv(GLenum(textureTarget), 0, GLenum(GL_TEXTURE_INTERNAL_FORMAT), &internalFormat)
    glGetTexLevelParameteriv(GLenum(textureTarget), 0, GLenum(GL_TEXTURE_RED_TYPE), &type)
    glGetTexLevelParameteriv(GLenum(textureTarget), 0, GLenum(GL_TEXTURE_WIDTH), &width)
    glGetTexLevelParameteriv(GLenum(textureTarget), 0, GLenum(GL_TEXTURE_HEIGHT), &height)
    
    NSLog("[media_kit][OpenGLHelpers] Texture format: internal=\(internalFormat), type=\(type), size=\(width)x\(height)")

    glTexParameteri(
      GLenum(textureTarget),
      GLenum(GL_TEXTURE_MAG_FILTER),
      GL_LINEAR
    )
    glTexParameteri(
      GLenum(textureTarget),
      GLenum(GL_TEXTURE_MIN_FILTER),
      GL_LINEAR
    )

    glViewport(0, 0, GLsizei(size.width), GLsizei(size.height))
    NSLog("[media_kit][OpenGLHelpers] Set viewport: \(size.width)x\(size.height)")

    var frameBuffer: GLuint = 0
    glGenFramebuffers(1, &frameBuffer)
    NSLog("[media_kit][OpenGLHelpers] Generated FBO: \(frameBuffer)")
    
    glBindFramebuffer(GLenum(GL_FRAMEBUFFER), frameBuffer)
    defer {
      glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
    }

    NSLog("[media_kit][OpenGLHelpers] Binding texture to FBO: texture=\(textureName), target=\(textureTarget)")
    glFramebufferTexture2D(
      GLenum(GL_FRAMEBUFFER),
      GLenum(GL_COLOR_ATTACHMENT0),
      GLenum(textureTarget),
      textureName,
      0
    )

    NSLog("[media_kit][OpenGLHelpers] Binding renderbuffer to FBO: renderBuffer=\(renderBuffer)")
    glFramebufferRenderbuffer(
      GLenum(GL_FRAMEBUFFER),
      GLenum(GL_DEPTH_ATTACHMENT),
      GLenum(GL_RENDERBUFFER),
      renderBuffer
    )

    // 检查FBO完整性
    let fboStatus = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
    NSLog("[media_kit][OpenGLHelpers] FBO status: \(fboStatus)")
    if fboStatus != GLenum(GL_FRAMEBUFFER_COMPLETE) {
      NSLog("[media_kit][OpenGLHelpers] ⚠️ FBO is not complete! Status: \(fboStatus)")
      
      // 检查各个attachment的状态
      var attachmentType = GLint(0)
      glGetFramebufferAttachmentParameteriv(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE), &attachmentType)
      NSLog("[media_kit][OpenGLHelpers] Color attachment type: \(attachmentType)")
      
      var attachmentStatus = GLint(0)
      glGetFramebufferAttachmentParameteriv(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME), &attachmentStatus)
      NSLog("[media_kit][OpenGLHelpers] Color attachment name: \(attachmentStatus)")
      
      glGetFramebufferAttachmentParameteriv(GLenum(GL_FRAMEBUFFER), GLenum(GL_DEPTH_ATTACHMENT), GLenum(GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE), &attachmentType)
      NSLog("[media_kit][OpenGLHelpers] Depth attachment type: \(attachmentType)")
    } else {
      NSLog("[media_kit][OpenGLHelpers] ✅ FBO is complete")
    }

    return frameBuffer
  }

  static public func deletePixelFormat(_ pixelFormat: CGLPixelFormatObj) {
    NSLog("[media_kit][OpenGLHelpers] Deleting pixel format: \(pixelFormat)")
    CGLReleasePixelFormat(pixelFormat)
  }

  static public func deleteContext(_ context: CGLContextObj) {
    NSLog("[media_kit][OpenGLHelpers] Deleting OpenGL context: \(context)")
    CGLSetCurrentContext(nil)
    CGLReleaseContext(context)
  }

  static public func deleteTextureCache(_ textureCache: CVOpenGLTextureCache) {
    NSLog("[media_kit][OpenGLHelpers] Flushing texture cache: \(textureCache)")
    CVOpenGLTextureCacheFlush(textureCache, 0)

    // 'CVOpenGLTextureCacheRelease' is unavailable: Core Foundation objects are
    // automatically memory managed
  }

  static public func deletePixeBuffer(
    _ context: CGLContextObj,
    _ pixelBuffer: CVPixelBuffer
  ) {
    NSLog("[media_kit][OpenGLHelpers] Deleting pixel buffer: \(pixelBuffer)")
    // 'CVPixelBufferRelease' is unavailable: Core Foundation objects are
    // automatically memory managed
  }

  // BUG: `glDeleteTextures` does not release `CVOpenGLTexture`.
  // `CVOpenGLTextureCache` retains a direct or indirect reference to
  // `IOSurface`, which causes a memory leak until `CVOpenGLTextureCache` is
  // released.
  static public func deleteTexture(
    _ context: CGLContextObj,
    _ texture: CVOpenGLTexture
  ) {
    NSLog("[media_kit][OpenGLHelpers] Deleting texture: \(texture)")
    CGLSetCurrentContext(context)
    defer {
      OpenGLHelpers.checkError("deleteTexture")
      CGLSetCurrentContext(nil)
    }

    var textureName: GLuint = CVOpenGLTextureGetName(texture)
    glDeleteTextures(1, &textureName)
  }

  static public func deleteRenderBuffer(
    _ context: CGLContextObj,
    _ renderBuffer: GLuint
  ) {
    NSLog("[media_kit][OpenGLHelpers] Deleting render buffer: \(renderBuffer)")
    CGLSetCurrentContext(context)
    defer {
      OpenGLHelpers.checkError("deleteRenderBuffer")
      CGLSetCurrentContext(nil)
    }

    var renderBuffer = renderBuffer
    glDeleteRenderbuffers(1, &renderBuffer)
  }

  static public func deleteFrameBuffer(
    _ context: CGLContextObj,
    _ frameBuffer: GLuint
  ) {
    NSLog("[media_kit][OpenGLHelpers] Deleting frame buffer: \(frameBuffer)")
    CGLSetCurrentContext(context)
    defer {
      OpenGLHelpers.checkError("deleteFrameBuffer")
      CGLSetCurrentContext(nil)
    }

    var frameBuffer = frameBuffer
    glDeleteFramebuffers(1, &frameBuffer)
  }

  static public func checkError(_ message: String) {
    let error = glGetError()
    if error == GL_NO_ERROR {
      return
    }

    NSLog("[media_kit][OpenGLHelpers] ⚠️ OpenGL error in \(message): \(error)")
  }

  static public func create2DTextureFromPixelBuffer(_ context: CGLContextObj, _ pixelBuffer: CVPixelBuffer) -> GLuint {
    NSLog("[media_kit][OpenGLHelpers] Creating GL_TEXTURE_2D from pixel buffer...")
    CGLSetCurrentContext(context)
    defer {
      OpenGLHelpers.checkError("create2DTextureFromPixelBuffer")
      CGLSetCurrentContext(nil)
    }
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    var texture: GLuint = 0
    glGenTextures(1, &texture)
    glBindTexture(GLenum(GL_TEXTURE_2D), texture)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
    // 绑定 IOSurface
    #if arch(x86_64) || arch(arm64)
    if let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() {
      let cglContext = context
      let cglPixelFormat = CGLGetPixelFormat(cglContext)
      // CGLTexImageIOSurface2D 绑定 IOSurface 到 GL_TEXTURE_2D
      let kCGLTexImageIOSurface2D: @convention(c) (CGLContextObj, GLenum, GLenum, GLsizei, GLsizei, GLenum, GLenum, IOSurfaceRef, GLuint) -> Void = unsafeBitCast(dlsym(dlopen(nil, RTLD_LAZY), "CGLTexImageIOSurface2D"), to: (@convention(c) (CGLContextObj, GLenum, GLenum, GLsizei, GLsizei, GLenum, GLenum, IOSurfaceRef, GLuint) -> Void).self)
      kCGLTexImageIOSurface2D(context, GLenum(GL_TEXTURE_2D), GLenum(GL_RGBA), GLsizei(width), GLsizei(height), GLenum(GL_BGRA), GLenum(GL_UNSIGNED_INT_8_8_8_8_REV), surface, 0)
      NSLog("[media_kit][OpenGLHelpers] CGLTexImageIOSurface2D called for GL_TEXTURE_2D")
    } else {
      NSLog("[media_kit][OpenGLHelpers] ⚠️ Failed to get IOSurface from pixel buffer!")
    }
    #endif
    glBindTexture(GLenum(GL_TEXTURE_2D), 0)
    NSLog("[media_kit][OpenGLHelpers] GL_TEXTURE_2D created: \(texture)")
    return texture
  }

  static public func createFrameBuffer2D(
    context: CGLContextObj,
    renderBuffer: GLuint,
    texture: GLuint,
    size: CGSize
  ) -> GLuint {
    CGLSetCurrentContext(context)
    defer {
      OpenGLHelpers.checkError("createFrameBuffer2D")
      CGLSetCurrentContext(nil)
    }

    NSLog("[media_kit][OpenGLHelpers] Creating FBO (2D) for size: \(size.width)x\(size.height)")
    glBindTexture(GLenum(GL_TEXTURE_2D), texture)
    defer {
      glBindTexture(GLenum(GL_TEXTURE_2D), 0)
    }
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
    glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
    glViewport(0, 0, GLsizei(size.width), GLsizei(size.height))
    NSLog("[media_kit][OpenGLHelpers] Set viewport: \(size.width)x\(size.height)")
    var frameBuffer: GLuint = 0
    glGenFramebuffers(1, &frameBuffer)
    NSLog("[media_kit][OpenGLHelpers] Generated FBO: \(frameBuffer)")
    glBindFramebuffer(GLenum(GL_FRAMEBUFFER), frameBuffer)
    defer {
      glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
    }
    NSLog("[media_kit][OpenGLHelpers] Binding texture to FBO: texture=\(texture), target=GL_TEXTURE_2D")
    glFramebufferTexture2D(
      GLenum(GL_FRAMEBUFFER),
      GLenum(GL_COLOR_ATTACHMENT0),
      GLenum(GL_TEXTURE_2D),
      texture,
      0
    )
    NSLog("[media_kit][OpenGLHelpers] Binding renderbuffer to FBO: renderBuffer=\(renderBuffer)")
    glFramebufferRenderbuffer(
      GLenum(GL_FRAMEBUFFER),
      GLenum(GL_DEPTH_ATTACHMENT),
      GLenum(GL_RENDERBUFFER),
      renderBuffer
    )
    let fboStatus = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
    NSLog("[media_kit][OpenGLHelpers] FBO status: \(fboStatus)")
    if fboStatus != GLenum(GL_FRAMEBUFFER_COMPLETE) {
      NSLog("[media_kit][OpenGLHelpers] ⚠️ FBO is not complete! Status: \(fboStatus)")
    } else {
      NSLog("[media_kit][OpenGLHelpers] ✅ FBO is complete")
    }
    return frameBuffer
  }

  static public func deleteTexture2D(_ context: CGLContextObj, _ texture: GLuint) {
    NSLog("[media_kit][OpenGLHelpers] Deleting GL_TEXTURE_2D: \(texture)")
    CGLSetCurrentContext(context)
    defer {
      OpenGLHelpers.checkError("deleteTexture2D")
      CGLSetCurrentContext(nil)
    }
    var tex = texture
    glDeleteTextures(1, &tex)
  }
}
