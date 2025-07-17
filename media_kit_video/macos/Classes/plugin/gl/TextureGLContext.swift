public class TextureGLContext {
  private let context: CGLContextObj
  private let renderBuffer: GLuint
  public let frameBuffer: GLuint
  public let texture: GLuint
  public let pixelBuffer: CVPixelBuffer

  init(
    context: CGLContextObj,
    textureCache: CVOpenGLTextureCache,
    size: CGSize
  ) {
    NSLog("[media_kit][TextureGLContext] Creating TextureGLContext for size: \(size.width)x\(size.height)")
    
    self.context = context

    NSLog("[media_kit][TextureGLContext] Creating pixel buffer...")
    self.pixelBuffer = OpenGLHelpers.createPixelBuffer(size)
    NSLog("[media_kit][TextureGLContext] Pixel buffer created: \(self.pixelBuffer)")

    NSLog("[media_kit][TextureGLContext] Creating GL_TEXTURE_2D from pixel buffer...")
    self.texture = OpenGLHelpers.create2DTextureFromPixelBuffer(context, pixelBuffer)
    NSLog("[media_kit][TextureGLContext] GL_TEXTURE_2D created: \(self.texture)")

    NSLog("[media_kit][TextureGLContext] Creating render buffer...")
    self.renderBuffer = OpenGLHelpers.createRenderBuffer(
      context,
      size
    )
    NSLog("[media_kit][TextureGLContext] Render buffer created: \(self.renderBuffer)")

    NSLog("[media_kit][TextureGLContext] Creating frame buffer...")
    self.frameBuffer = OpenGLHelpers.createFrameBuffer2D(
      context: context,
      renderBuffer: renderBuffer,
      texture: texture,
      size: size
    )
    NSLog("[media_kit][TextureGLContext] Frame buffer created: \(self.frameBuffer)")
    
    NSLog("[media_kit][TextureGLContext] TextureGLContext creation completed")
  }

  deinit {
    NSLog("[media_kit][TextureGLContext] Destroying TextureGLContext: FBO=\(frameBuffer), texture=\(texture), renderBuffer=\(renderBuffer)")
    OpenGLHelpers.deletePixeBuffer(context, pixelBuffer)
    OpenGLHelpers.deleteTexture2D(context, texture)
    OpenGLHelpers.deleteRenderBuffer(context, renderBuffer)
    OpenGLHelpers.deleteFrameBuffer(context, frameBuffer)
  }
}
