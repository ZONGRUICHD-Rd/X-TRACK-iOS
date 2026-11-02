#ifndef LV_FS_IOS_H
#define LV_FS_IOS_H

#ifdef __cplusplus
extern "C" {
#endif

/* Register the '/' drive, rooted at rootPath (no trailing slash needed). */
void lv_fs_ios_init(const char* rootPath);

#ifdef __cplusplus
}
#endif

#endif
