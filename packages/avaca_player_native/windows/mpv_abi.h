#ifndef AVACA_PLAYER_NATIVE_WINDOWS_MPV_ABI_H_
#define AVACA_PLAYER_NATIVE_WINDOWS_MPV_ABI_H_

#include <stddef.h>
#include <stdint.h>

// This file deliberately contains only the libmpv ABI used by AVACA.  The
// Windows plugin loads libmpv-2.dll at runtime, so the application does not
// link to an ambient or PATH-selected copy of libmpv.

typedef struct mpv_handle mpv_handle;
typedef struct mpv_render_context mpv_render_context;

typedef enum mpv_format {
  MPV_FORMAT_NONE = 0,
  MPV_FORMAT_STRING = 1,
  MPV_FORMAT_OSD_STRING = 2,
  MPV_FORMAT_FLAG = 3,
  MPV_FORMAT_INT64 = 4,
  MPV_FORMAT_DOUBLE = 5,
  MPV_FORMAT_NODE = 6,
  MPV_FORMAT_NODE_ARRAY = 7,
  MPV_FORMAT_NODE_MAP = 8,
  MPV_FORMAT_BYTE_ARRAY = 9,
} mpv_format;

typedef struct mpv_node_list mpv_node_list;
typedef struct mpv_byte_array mpv_byte_array;

typedef struct mpv_node {
  union {
    char* string;
    int flag;
    int64_t int64;
    double double_;
    mpv_node_list* list;
    mpv_byte_array* ba;
  } u;
  mpv_format format;
} mpv_node;

struct mpv_node_list {
  int num;
  mpv_node* values;
  char** keys;
};

typedef enum mpv_event_id {
  MPV_EVENT_NONE = 0,
  MPV_EVENT_SHUTDOWN = 1,
  MPV_EVENT_LOG_MESSAGE = 2,
  MPV_EVENT_GET_PROPERTY_REPLY = 3,
  MPV_EVENT_SET_PROPERTY_REPLY = 4,
  MPV_EVENT_COMMAND_REPLY = 5,
  MPV_EVENT_START_FILE = 6,
  MPV_EVENT_END_FILE = 7,
  MPV_EVENT_FILE_LOADED = 8,
  MPV_EVENT_IDLE = 11,
  MPV_EVENT_TICK = 14,
  MPV_EVENT_CLIENT_MESSAGE = 16,
  MPV_EVENT_VIDEO_RECONFIG = 17,
  MPV_EVENT_AUDIO_RECONFIG = 18,
  MPV_EVENT_SEEK = 20,
  MPV_EVENT_PLAYBACK_RESTART = 21,
  MPV_EVENT_PROPERTY_CHANGE = 22,
  MPV_EVENT_QUEUE_OVERFLOW = 24,
  MPV_EVENT_HOOK = 25,
} mpv_event_id;

typedef struct mpv_event_property {
  const char* name;
  mpv_format format;
  void* data;
} mpv_event_property;

typedef struct mpv_event_end_file {
  int reason;
  int error;
  int64_t playlist_entry_id;
  int64_t playlist_insert_id;
  int64_t playlist_insert_num_entries;
} mpv_event_end_file;

typedef struct mpv_event {
  mpv_event_id event_id;
  int error;
  uint64_t reply_userdata;
  void* data;
} mpv_event;

typedef enum mpv_render_param_type {
  MPV_RENDER_PARAM_INVALID = 0,
  MPV_RENDER_PARAM_API_TYPE = 1,
  MPV_RENDER_PARAM_OPENGL_INIT_PARAMS = 2,
  MPV_RENDER_PARAM_OPENGL_FBO = 3,
  MPV_RENDER_PARAM_FLIP_Y = 4,
  MPV_RENDER_PARAM_DEPTH = 5,
  MPV_RENDER_PARAM_ICC = 6,
  MPV_RENDER_PARAM_AMBIENT_LIGHT = 7,
  MPV_RENDER_PARAM_X11_DISPLAY = 8,
  MPV_RENDER_PARAM_WL_DISPLAY = 9,
  MPV_RENDER_PARAM_ADVANCED_CONTROL = 10,
  MPV_RENDER_PARAM_NEXT_FRAME_INFO = 11,
  MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME = 12,
  MPV_RENDER_PARAM_SKIP_RENDERING = 13,
} mpv_render_param_type;

typedef struct mpv_render_param {
  mpv_render_param_type type;
  void* data;
} mpv_render_param;

typedef struct mpv_opengl_init_params {
  void* (*get_proc_address)(void* ctx, const char* name);
  void* get_proc_address_ctx;
} mpv_opengl_init_params;

typedef struct mpv_opengl_fbo {
  int fbo;
  int w;
  int h;
  int internal_format;
} mpv_opengl_fbo;

typedef void (*mpv_render_update_fn)(void* cb_ctx);

typedef mpv_handle*(__cdecl* mpv_create_fn)();
typedef int(__cdecl* mpv_initialize_fn)(mpv_handle* ctx);
typedef void(__cdecl* mpv_terminate_destroy_fn)(mpv_handle* ctx);
typedef int(__cdecl* mpv_set_option_string_fn)(mpv_handle* ctx,
                                                const char* name,
                                                const char* value);
typedef int(__cdecl* mpv_set_property_string_fn)(mpv_handle* ctx,
                                                  const char* name,
                                                  const char* value);
typedef int(__cdecl* mpv_get_property_fn)(mpv_handle* ctx,
                                          const char* name,
                                          mpv_format format,
                                          void* data);
typedef char*(__cdecl* mpv_get_property_string_fn)(mpv_handle* ctx,
                                                    const char* name);
typedef int(__cdecl* mpv_observe_property_fn)(mpv_handle* ctx,
                                              uint64_t reply_userdata,
                                              const char* name,
                                              mpv_format format);
typedef int(__cdecl* mpv_unobserve_property_fn)(mpv_handle* ctx,
                                                uint64_t reply_userdata);
typedef int(__cdecl* mpv_request_event_fn)(mpv_handle* ctx,
                                            mpv_event_id event,
                                            int enable);
typedef int(__cdecl* mpv_command_fn)(mpv_handle* ctx, const char** args);
typedef mpv_event*(__cdecl* mpv_wait_event_fn)(mpv_handle* ctx,
                                               double timeout);
typedef void(__cdecl* mpv_wakeup_fn)(mpv_handle* ctx);
typedef void(__cdecl* mpv_free_fn)(void* data);
typedef void(__cdecl* mpv_free_node_contents_fn)(mpv_node* node);
typedef const char*(__cdecl* mpv_error_string_fn)(int error);
typedef unsigned long(__cdecl* mpv_client_api_version_fn)();

typedef int(__cdecl* mpv_render_context_create_fn)(mpv_render_context** res,
                                                    mpv_handle* ctx,
                                                    mpv_render_param* params);
typedef void(__cdecl* mpv_render_context_set_update_callback_fn)(
    mpv_render_context* ctx,
    mpv_render_update_fn callback,
    void* callback_ctx);
typedef uint64_t(__cdecl* mpv_render_context_update_fn)(
    mpv_render_context* ctx);
typedef int(__cdecl* mpv_render_context_render_fn)(mpv_render_context* ctx,
                                                   mpv_render_param* params);
typedef void(__cdecl* mpv_render_context_report_swap_fn)(
    mpv_render_context* ctx);
typedef void(__cdecl* mpv_render_context_free_fn)(mpv_render_context* ctx);

#define MPV_RENDER_API_TYPE_OPENGL "opengl"
#define MPV_RENDER_UPDATE_FRAME (1ULL << 0)

#endif  // AVACA_PLAYER_NATIVE_WINDOWS_MPV_ABI_H_
