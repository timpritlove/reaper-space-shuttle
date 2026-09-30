#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/// Layout-compatible mirror of `reaper_plugin_info_t` from the REAPER SDK (reaper_plugin.h).
typedef struct RBPluginInfo {
    int callerVersion;
    void *mainWindow;
    int (*Register)(const char *name, void *infostruct);
    void *(*GetFunc)(const char *name);
} RBPluginInfo;

/// Layout-compatible mirror of `custom_action_register_t`, used with `Register("custom_action", …)`.
typedef struct RBCustomAction {
    int uniqueSectionId;
    const char *idStr;
    const char *name;
    void *extra;
} RBCustomAction;

#ifdef __cplusplus
}
#endif
