#ifndef AVACA_ANDROID_GLOB_COMPAT_H
#define AVACA_ANDROID_GLOB_COMPAT_H

#if defined(__ANDROID__) && defined(__ANDROID_API__) && __ANDROID_API__ < 28

#include <glob.h>

#if defined(__GNUC__) || defined(__clang__)
#define AVACA_ANDROID_GLOB_COMPAT_UNUSED __attribute__((unused))
#else
#define AVACA_ANDROID_GLOB_COMPAT_UNUSED
#endif

static AVACA_ANDROID_GLOB_COMPAT_UNUSED int
avaca_android_glob_compat(
    const char* Pattern,
    int Flags,
    int (*ErrorFunction)(const char*, int),
    glob_t* Result)
{
    (void)Pattern;
    (void)Flags;
    (void)ErrorFunction;
    (void)Result;
    return GLOB_NOMATCH;
}

static AVACA_ANDROID_GLOB_COMPAT_UNUSED void
avaca_android_globfree_compat(glob_t* Result)
{
    (void)Result;
}

#define glob avaca_android_glob_compat
#define globfree avaca_android_globfree_compat

#undef AVACA_ANDROID_GLOB_COMPAT_UNUSED

#endif

#endif
