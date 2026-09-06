#ifndef AVACA_PLAYER_NATIVE_WINDOWS_ANGLE_ABI_H_
#define AVACA_PLAYER_NATIVE_WINDOWS_ANGLE_ABI_H_

#include <stdint.h>

// Minimal EGL/GLES ABI declarations.  ANGLE is loaded from the AVACA bundle
// by absolute path and is never selected from PATH or the system OpenGL
// loader.  The bridge intentionally exposes no CPU pixel-buffer fallback.
using EGLBoolean = unsigned int;
using EGLint = int;
using EGLenum = unsigned int;
using EGLDisplay = void*;
using EGLConfig = void*;
using EGLSurface = void*;
using EGLContext = void*;
using EGLClientBuffer = void*;

constexpr EGLBoolean EGL_FALSE = 0;
constexpr EGLBoolean EGL_TRUE = 1;
constexpr EGLDisplay EGL_NO_DISPLAY = nullptr;
constexpr EGLSurface EGL_NO_SURFACE = nullptr;
constexpr EGLContext EGL_NO_CONTEXT = nullptr;

constexpr EGLint EGL_NONE = 0x3038;
constexpr EGLint EGL_WIDTH = 0x3057;
constexpr EGLint EGL_HEIGHT = 0x3056;
constexpr EGLint EGL_TEXTURE_FORMAT = 0x3080;
constexpr EGLint EGL_TEXTURE_TARGET = 0x3081;
constexpr EGLint EGL_TEXTURE_RGBA = 0x305E;
constexpr EGLint EGL_TEXTURE_2D = 0x305F;
constexpr EGLint EGL_BACK_BUFFER = 0x3084;
constexpr EGLint EGL_RENDERABLE_TYPE = 0x3040;
constexpr EGLint EGL_SURFACE_TYPE = 0x3033;
constexpr EGLint EGL_RED_SIZE = 0x3024;
constexpr EGLint EGL_GREEN_SIZE = 0x3023;
constexpr EGLint EGL_BLUE_SIZE = 0x3022;
constexpr EGLint EGL_ALPHA_SIZE = 0x3021;
constexpr EGLint EGL_DEPTH_SIZE = 0x3025;
constexpr EGLint EGL_STENCIL_SIZE = 0x3026;
constexpr EGLint EGL_PBUFFER_BIT = 0x0001;
constexpr EGLint EGL_OPENGL_ES2_BIT = 0x0004;
constexpr EGLint EGL_CONTEXT_CLIENT_VERSION = 0x3098;
constexpr EGLenum EGL_OPENGL_ES_API = 0x30A0;

constexpr EGLenum EGL_PLATFORM_ANGLE_ANGLE = 0x3202;
constexpr EGLint EGL_PLATFORM_ANGLE_TYPE_ANGLE = 0x3203;
constexpr EGLint EGL_PLATFORM_ANGLE_TYPE_D3D11_ANGLE = 0x3208;
constexpr EGLint EGL_PLATFORM_ANGLE_ENABLE_AUTOMATIC_TRIM_ANGLE = 0x320F;
constexpr EGLint EGL_EXPERIMENTAL_PRESENT_PATH_ANGLE = 0x33A4;
constexpr EGLint EGL_EXPERIMENTAL_PRESENT_PATH_FAST_ANGLE = 0x33A9;
constexpr EGLenum EGL_D3D_TEXTURE_2D_SHARE_HANDLE_ANGLE = 0x3200;

constexpr unsigned int GL_VERSION = 0x1F02;

using eglGetProcAddress_fn = void* (*)(const char* name);
using eglGetPlatformDisplayEXT_fn = EGLDisplay (*)(EGLenum platform,
                                                   void* native_display,
                                                   const EGLint* attrib_list);
using eglInitialize_fn = EGLBoolean (*)(EGLDisplay display,
                                        EGLint* major,
                                        EGLint* minor);
using eglTerminate_fn = EGLBoolean (*)(EGLDisplay display);
using eglChooseConfig_fn = EGLBoolean (*)(EGLDisplay display,
                                          const EGLint* attrib_list,
                                          EGLConfig* configs,
                                          EGLint config_size,
                                          EGLint* num_config);
using eglBindAPI_fn = EGLBoolean (*)(EGLenum api);
using eglCreateContext_fn = EGLContext (*)(EGLDisplay display,
                                           EGLConfig config,
                                           EGLContext share_context,
                                           const EGLint* attrib_list);
using eglDestroyContext_fn = EGLBoolean (*)(EGLDisplay display,
                                            EGLContext context);
using eglCreatePbufferFromClientBuffer_fn = EGLSurface (*)(
    EGLDisplay display,
    EGLenum buftype,
    EGLClientBuffer buffer,
    EGLConfig config,
    const EGLint* attrib_list);
using eglDestroySurface_fn = EGLBoolean (*)(EGLDisplay display,
                                            EGLSurface surface);
using eglMakeCurrent_fn = EGLBoolean (*)(EGLDisplay display,
                                         EGLSurface draw,
                                         EGLSurface read,
                                         EGLContext context);
using eglBindTexImage_fn = EGLBoolean (*)(EGLDisplay display,
                                          EGLSurface surface,
                                          EGLint buffer);
using eglReleaseTexImage_fn = EGLBoolean (*)(EGLDisplay display,
                                             EGLSurface surface,
                                             EGLint buffer);
using eglSwapBuffers_fn = EGLBoolean (*)(EGLDisplay display,
                                         EGLSurface surface);
using eglGetError_fn = EGLint (*)();
using glFinish_fn = void (*)();
using glGetString_fn = const unsigned char* (*)(unsigned int name);

#endif  // AVACA_PLAYER_NATIVE_WINDOWS_ANGLE_ABI_H_
