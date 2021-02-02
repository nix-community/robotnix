/*
 * SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
 * SPDX-License-Identifier: MIT
 */

#define _GNU_SOURCE

#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include <unistd.h>

#include <sched.h>

#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>

// TODO: No real error handling. Need to make this more robust.

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "Usage: fakeuser <uid> <gid> [command]\n");
        exit(1);
    }

    uid_t uid = getuid();
    gid_t gid = getgid();

    unshare(CLONE_NEWUSER);

    FILE *f;
    f = fopen("/proc/self/setgroups", "w");
    fprintf(f, "deny");
    fclose(f);
    f = fopen("/proc/self/uid_map", "w");
    fprintf(f, "%d %d 1", atoi(argv[1]), uid);
    fclose(f);
    f = fopen("/proc/self/gid_map", "w");
    fprintf(f, "%d %d 1", atoi(argv[2]), gid);
    fclose(f);

    if (argc >= 4)
        return execvp(argv[3], argv+3);
    else
        return execl("/bin/sh", "/bin/sh", NULL);
}
