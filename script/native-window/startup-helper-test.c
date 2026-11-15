#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
static char hosts_path[1024], temp_path[1024];
#define MGB_HOSTS_PATH hosts_path
#define MGB_HOSTS_TEMP temp_path
#define MGB_HOSTS_OWNER getuid()
#define main helper_entry_unused
#include "startup-helper.c"
#undef main

static void save(const char *text) { FILE *f=fopen(hosts_path,"w");assert(f);assert(fputs(text,f)>=0);assert(!fclose(f)); }
static void expect(const char *text) { char data[4096]={0};FILE *f=fopen(hosts_path,"r");assert(f);fread(data,1,sizeof(data)-1,f);fclose(f);assert(!strcmp(data,text)); }
int main(void) {
    char root[]="/tmp/hoyobridge-startup-helper-test-XXXXXX";assert(mkdtemp(root));
    snprintf(hosts_path,sizeof(hosts_path),"%s/hosts",root);
    snprintf(temp_path,sizeof(temp_path),"%s/.temp-XXXXXX",root);
    save("127.0.0.1 localhost\n# preserve\n");
    assert(rewrite_hosts(1)==0);expect("127.0.0.1 localhost\n# preserve\n" ENTRY);
    assert(rewrite_hosts(0)==0);expect("127.0.0.1 localhost\n# preserve\n");
    assert(rewrite_hosts(0)==0);
    save("127.0.0.1 localhost\n" ENTRY "10.0.0.1 added-by-user\n");
    assert(rewrite_hosts(0)==0);expect("127.0.0.1 localhost\n10.0.0.1 added-by-user\n");
    save("# example: " ENTRY);
    assert(rewrite_hosts(0)==0);expect("# example: " ENTRY);
    save("1.2.3.4 globaldp-prod-cn01.bhsr.com\n");
    assert(rewrite_hosts(1)!=0);expect("1.2.3.4 globaldp-prod-cn01.bhsr.com\n");
    save("no final newline");assert(rewrite_hosts(1)!=0);expect("no final newline");
    unlink(hosts_path);assert(symlink("/etc/hosts",hosts_path)==0);assert(rewrite_hosts(1)!=0);
    unlink(hosts_path);rmdir(root);
    puts("PASS: bounded startup marker add/restore, unrelated entries, invalid files and symlinks");
    return 0;
}
