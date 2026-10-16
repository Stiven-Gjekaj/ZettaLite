#import "ZLVideoView.h"
#import <OpenGLES/ES2/gl.h>
#import <QuartzCore/QuartzCore.h>

static const char *ZLVertexShader =
    "attribute vec2 position;\n"
    "attribute vec2 coordinate;\n"
    "varying vec2 place;\n"
    "void main() {\n"
    "    gl_Position = vec4(position, 0.0, 1.0);\n"
    "    place = coordinate;\n"
    "}\n";

// The matrix and the offset come from the color standard and the range.
static const char *ZLFragmentShader =
    "precision mediump float;\n"
    "varying vec2 place;\n"
    "uniform sampler2D lumaTexture;\n"
    "uniform sampler2D blueTexture;\n"
    "uniform sampler2D redTexture;\n"
    "uniform mat3 matrix;\n"
    "uniform vec3 offset;\n"
    "void main() {\n"
    "    vec3 yuv = vec3(texture2D(lumaTexture, place).r, texture2D(blueTexture, place).r, texture2D(redTexture, place).r);\n"
    "    gl_FragColor = vec4(matrix * (yuv - offset), 1.0);\n"
    "}\n";

@interface ZLVideoView () {
    GLuint _framebuffer;
    GLuint _renderbuffer;
    GLuint _program;
    GLuint _textures[3];
    GLint _matrixUniform;
    GLint _offsetUniform;
    GLint _width;
    GLint _height;
}
@property (nonatomic, strong) EAGLContext *context;
@property (nonatomic, strong) ZLVideoFrame *lastFrame;
@end

@implementation ZLVideoView

+ (Class)layerClass {
    return [CAEAGLLayer class];
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor blackColor];
        self.contentScaleFactor = [UIScreen mainScreen].scale;
        CAEAGLLayer *layer = (CAEAGLLayer *)self.layer;
        layer.opaque = YES;
        layer.drawableProperties = @{ kEAGLDrawablePropertyRetainedBacking: @NO,
                                      kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8 };
    }
    return self;
}

- (void)dealloc {
    [self releaseGL];
}

static GLuint ZLCompile(GLenum type, const char *source) {
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, NULL);
    glCompileShader(shader);
    GLint ok = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

- (BOOL)setUpGL {
    if (self.context) return YES;
    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    if (!self.context || ![EAGLContext setCurrentContext:self.context]) return NO;
    GLuint vertex = ZLCompile(GL_VERTEX_SHADER, ZLVertexShader);
    GLuint fragment = ZLCompile(GL_FRAGMENT_SHADER, ZLFragmentShader);
    _program = glCreateProgram();
    glAttachShader(_program, vertex);
    glAttachShader(_program, fragment);
    glBindAttribLocation(_program, 0, "position");
    glBindAttribLocation(_program, 1, "coordinate");
    glLinkProgram(_program);
    glDeleteShader(vertex);
    glDeleteShader(fragment);
    glUseProgram(_program);
    glUniform1i(glGetUniformLocation(_program, "lumaTexture"), 0);
    glUniform1i(glGetUniformLocation(_program, "blueTexture"), 1);
    glUniform1i(glGetUniformLocation(_program, "redTexture"), 2);
    _matrixUniform = glGetUniformLocation(_program, "matrix");
    _offsetUniform = glGetUniformLocation(_program, "offset");
    glGenTextures(3, _textures);
    for (int i = 0; i < 3; i++) {
        glBindTexture(GL_TEXTURE_2D, _textures[i]);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    }
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    return YES;
}

- (void)makeFramebuffer {
    [EAGLContext setCurrentContext:self.context];
    if (_framebuffer) {
        glDeleteFramebuffers(1, &_framebuffer);
        glDeleteRenderbuffers(1, &_renderbuffer);
    }
    glGenFramebuffers(1, &_framebuffer);
    glGenRenderbuffers(1, &_renderbuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);
    glBindRenderbuffer(GL_RENDERBUFFER, _renderbuffer);
    [self.context renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer *)self.layer];
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _renderbuffer);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &_width);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_height);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (![self setUpGL]) return;
    [self makeFramebuffer];
    [self redraw];
}

- (void)releaseGL {
    if (!self.context) return;
    [EAGLContext setCurrentContext:self.context];
    glFinish();
    if (_framebuffer) glDeleteFramebuffers(1, &_framebuffer);
    if (_renderbuffer) glDeleteRenderbuffers(1, &_renderbuffer);
    glDeleteTextures(3, _textures);
    if (_program) glDeleteProgram(_program);
    _framebuffer = _renderbuffer = _program = 0;
    [EAGLContext setCurrentContext:nil];
    self.context = nil;
}

- (void)setGravity:(ZLVideoGravity)gravity {
    _gravity = gravity;
    [self redraw];
}

- (void)showFrame:(ZLVideoFrame *)frame {
    if (!frame || ![self setUpGL]) return;
    if (!_framebuffer) [self makeFramebuffer];
    [EAGLContext setCurrentContext:self.context];
    int widths[3] = {frame.width, (frame.width + 1) / 2, (frame.width + 1) / 2};
    int heights[3] = {frame.height, (frame.height + 1) / 2, (frame.height + 1) / 2};
    NSData *planes[3] = {frame.luma, frame.blue, frame.red};
    for (int i = 0; i < 3; i++) {
        glActiveTexture(GL_TEXTURE0 + i);
        glBindTexture(GL_TEXTURE_2D, _textures[i]);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, widths[i], heights[i], 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, planes[i].bytes);
    }
    self.lastFrame = frame;
    [self draw];
}

- (void)redraw {
    if (self.lastFrame && self.context && _framebuffer) [self draw];
}

- (void)draw {
    ZLVideoFrame *frame = self.lastFrame;
    [EAGLContext setCurrentContext:self.context];
    glBindFramebuffer(GL_FRAMEBUFFER, _framebuffer);
    glViewport(0, 0, _width, _height);
    glClearColor(0, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    glUseProgram(_program);

    // BT.601 or BT.709, in limited or full range.
    GLfloat bt601[9] = {1, 1, 1, 0, -0.344136f, 1.772f, 1.402f, -0.714136f, 0};
    GLfloat bt709[9] = {1, 1, 1, 0, -0.187324f, 1.8556f, 1.5748f, -0.468124f, 0};
    GLfloat matrix[9];
    memcpy(matrix, frame.hd ? bt709 : bt601, sizeof(matrix));
    GLfloat offset[3] = {0, 0.5f, 0.5f};
    if (!frame.fullRange) {
        // Limited range: luma 16 to 235, chroma 16 to 240.
        offset[0] = 16.0f / 255;
        GLfloat lumaScale = 255.0f / 219, chromaScale = 255.0f / 224;
        for (int column = 0; column < 3; column++) {
            matrix[column * 3 + 0] *= column == 0 ? lumaScale : chromaScale;
            matrix[column * 3 + 1] *= column == 0 ? lumaScale : chromaScale;
            matrix[column * 3 + 2] *= column == 0 ? lumaScale : chromaScale;
        }
    }
    glUniformMatrix3fv(_matrixUniform, 1, GL_FALSE, matrix);
    glUniform3fv(_offsetUniform, 1, offset);

    // The quad keeps the aspect of the picture.
    double aspect = frame.aspect > 0 ? frame.aspect : (double)frame.width / MAX(frame.height, 1);
    double viewAspect = (double)_width / MAX(_height, 1);
    GLfloat x = 1, y = 1;
    BOOL wider = aspect > viewAspect;
    if (self.gravity == ZLVideoGravityFit) {
        if (wider) y = (GLfloat)(viewAspect / aspect);
        else x = (GLfloat)(aspect / viewAspect);
    } else {
        if (wider) x = (GLfloat)(aspect / viewAspect);
        else y = (GLfloat)(viewAspect / aspect);
    }
    GLfloat positions[8] = {-x, -y, x, -y, -x, y, x, y};
    GLfloat coordinates[8] = {0, 1, 1, 1, 0, 0, 1, 0};
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, positions);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 0, coordinates);
    glEnableVertexAttribArray(1);
    for (int i = 0; i < 3; i++) {
        glActiveTexture(GL_TEXTURE0 + i);
        glBindTexture(GL_TEXTURE_2D, _textures[i]);
    }
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    glBindRenderbuffer(GL_RENDERBUFFER, _renderbuffer);
    [self.context presentRenderbuffer:GL_RENDERBUFFER];
}

@end
