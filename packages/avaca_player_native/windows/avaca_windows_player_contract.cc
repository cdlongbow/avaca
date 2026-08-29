#include "angle_abi.h"
#include "mpv_abi.h"

#include <flutter_texture_registrar.h>

#include <cstddef>

namespace {

// These checks guard the ABI subset used by the dynamic loader and the
// Flutter GPU descriptor.  They intentionally fail at compile time if the
// checked-in declarations drift from the libmpv/Flutter contracts.
static_assert(MPV_FORMAT_NODE == 6);
static_assert(MPV_FORMAT_NODE_MAP == 8);
static_assert(MPV_RENDER_PARAM_INVALID == 0);
static_assert(MPV_RENDER_PARAM_OPENGL_FBO == 3);
static_assert(sizeof(mpv_node) == 16);
static_assert(offsetof(mpv_event, data) == 16);
static_assert(sizeof(FlutterDesktopGpuSurfaceDescriptor) >=
              sizeof(void*) * 4);
static_assert(EGL_D3D_TEXTURE_2D_SHARE_HANDLE_ANGLE == 0x3200);

}  // namespace
