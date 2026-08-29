#ifndef AVACA_PLAYER_NATIVE_PLUGIN_H_
#define AVACA_PLAYER_NATIVE_PLUGIN_H_

#include <flutter_plugin_registrar.h>

#if defined(_WIN32)
#define AVACA_PLAYER_NATIVE_EXPORT __declspec(dllexport)
#else
#define AVACA_PLAYER_NATIVE_EXPORT
#endif

AVACA_PLAYER_NATIVE_EXPORT void AvacaPlayerNativePluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#endif  // AVACA_PLAYER_NATIVE_PLUGIN_H_
