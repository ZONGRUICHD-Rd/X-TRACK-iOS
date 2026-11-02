/*
 * X-TRACK iOS port - LVGL file system driver.
 * Maps the LVGL drive letter '/' (as used by X-TRACK: "/MAP/...", "/Track/...")
 * onto a runtime directory (the app's Documents folder).
 */
#include "lv_fs_ios.h"
#include "lvgl/lvgl.h"

#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <dirent.h>
#include <sys/stat.h>

static char s_root[1024] = ".";

static void make_path(char* buf, size_t size, const char* path)
{
    while (*path == '/') path++;
    snprintf(buf, size, "%s/%s", s_root, path);
}

static void* fs_open(lv_fs_drv_t* drv, const char* path, lv_fs_mode_t mode)
{
    (void)drv;
    const char* flags = "rb";
    if (mode == LV_FS_MODE_WR) flags = "wb";
    else if (mode == LV_FS_MODE_RD) flags = "rb";
    else if (mode == (LV_FS_MODE_WR | LV_FS_MODE_RD)) flags = "wb+";

    char buf[1280];
    make_path(buf, sizeof(buf), path);
    FILE* f = fopen(buf, flags);
    if (f) fseek(f, 0, SEEK_SET);
    return f;
}

static lv_fs_res_t fs_close(lv_fs_drv_t* drv, void* file_p)
{
    (void)drv;
    fclose((FILE*)file_p);
    return LV_FS_RES_OK;
}

static lv_fs_res_t fs_read(lv_fs_drv_t* drv, void* file_p, void* buf, uint32_t btr, uint32_t* br)
{
    (void)drv;
    size_t n = fread(buf, 1, btr, (FILE*)file_p);
    if (br) *br = (uint32_t)n;
    return ferror((FILE*)file_p) ? LV_FS_RES_FS_ERR : LV_FS_RES_OK;
}

static lv_fs_res_t fs_write(lv_fs_drv_t* drv, void* file_p, const void* buf, uint32_t btw, uint32_t* bw)
{
    (void)drv;
    size_t n = fwrite(buf, 1, btw, (FILE*)file_p);
    if (bw) *bw = (uint32_t)n;
    return n == btw ? LV_FS_RES_OK : LV_FS_RES_FS_ERR;
}

static lv_fs_res_t fs_seek(lv_fs_drv_t* drv, void* file_p, uint32_t pos, lv_fs_whence_t whence)
{
    (void)drv;
    int w = SEEK_SET;
    if (whence == LV_FS_SEEK_CUR) w = SEEK_CUR;
    else if (whence == LV_FS_SEEK_END) w = SEEK_END;
    return fseek((FILE*)file_p, (long)pos, w) == 0 ? LV_FS_RES_OK : LV_FS_RES_FS_ERR;
}

static lv_fs_res_t fs_tell(lv_fs_drv_t* drv, void* file_p, uint32_t* pos_p)
{
    (void)drv;
    *pos_p = (uint32_t)ftell((FILE*)file_p);
    return LV_FS_RES_OK;
}

typedef struct
{
    DIR* dir;
    char path[1280];
} ios_dir_t;

static void* fs_dir_open(lv_fs_drv_t* drv, const char* path)
{
    (void)drv;
    ios_dir_t* d = (ios_dir_t*)lv_mem_alloc(sizeof(ios_dir_t));
    if (!d) return NULL;
    make_path(d->path, sizeof(d->path), path);
    d->dir = opendir(d->path);
    if (!d->dir)
    {
        lv_mem_free(d);
        return NULL;
    }
    return d;
}

static lv_fs_res_t fs_dir_read(lv_fs_drv_t* drv, void* dir_p, char* fn)
{
    (void)drv;
    ios_dir_t* d = (ios_dir_t*)dir_p;
    struct dirent* entry;
    fn[0] = '\0';

    while ((entry = readdir(d->dir)) != NULL)
    {
        /* Skip ".", ".." and hidden entries (.DS_Store, .Trash, ...) */
        if (entry->d_name[0] == '.')
        {
            continue;
        }

        int isDir = (entry->d_type == DT_DIR);
        if (entry->d_type == DT_UNKNOWN)
        {
            char full[1600];
            struct stat st;
            snprintf(full, sizeof(full), "%s/%s", d->path, entry->d_name);
            isDir = (stat(full, &st) == 0 && S_ISDIR(st.st_mode));
        }

        if (isDir)
        {
            /* Callers use 128-byte buffers */
            fn[0] = '/';
            strncpy(fn + 1, entry->d_name, 126);
            fn[127] = '\0';
        }
        else
        {
            strncpy(fn, entry->d_name, 127);
            fn[127] = '\0';
        }
        break;
    }
    return LV_FS_RES_OK;
}

static lv_fs_res_t fs_dir_close(lv_fs_drv_t* drv, void* dir_p)
{
    (void)drv;
    ios_dir_t* d = (ios_dir_t*)dir_p;
    closedir(d->dir);
    lv_mem_free(d);
    return LV_FS_RES_OK;
}

void lv_fs_ios_init(const char* rootPath)
{
    if (rootPath && rootPath[0])
    {
        strncpy(s_root, rootPath, sizeof(s_root) - 1);
        s_root[sizeof(s_root) - 1] = '\0';
        size_t len = strlen(s_root);
        while (len > 1 && s_root[len - 1] == '/')
        {
            s_root[--len] = '\0';
        }
    }

    static lv_fs_drv_t fs_drv;
    lv_fs_drv_init(&fs_drv);
    fs_drv.letter = '/';
    fs_drv.open_cb = fs_open;
    fs_drv.close_cb = fs_close;
    fs_drv.read_cb = fs_read;
    fs_drv.write_cb = fs_write;
    fs_drv.seek_cb = fs_seek;
    fs_drv.tell_cb = fs_tell;
    fs_drv.dir_open_cb = fs_dir_open;
    fs_drv.dir_read_cb = fs_dir_read;
    fs_drv.dir_close_cb = fs_dir_close;
    lv_fs_drv_register(&fs_drv);
}
