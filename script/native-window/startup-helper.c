// Fixed-purpose launchd helper: temporarily block one Star Rail startup host.
// No arbitrary command, filename, hostname or duration is accepted from clients.
#include <launch.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <sys/wait.h>
#include <poll.h>
#include <fcntl.h>
#include <unistd.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

#define ENTRY "0.0.0.0 globaldp-prod-cn01.bhsr.com # hoyobridge-startup-v1\n"
#ifndef MGB_HOSTS_PATH
#define MGB_HOSTS_PATH "/etc/hosts"
#define MGB_HOSTS_TEMP "/etc/.hoyobridge-hosts-XXXXXX"
#define MGB_HOSTS_OWNER 0
#endif
#ifndef MGB_HELPER_EXPECTED_EUID
#define MGB_HELPER_EXPECTED_EUID 0
#endif
static volatile sig_atomic_t stopping;
static void stop_signal(int value) { (void)value; stopping=1; }

static int rewrite_hosts(int add) {
    int fd=open(MGB_HOSTS_PATH,O_RDWR|O_NOFOLLOW|O_CLOEXEC);
    if(fd<0)return -1;
    struct stat info;
    if(fstat(fd,&info)||!S_ISREG(info.st_mode)||info.st_uid!=MGB_HOSTS_OWNER||info.st_size<0||info.st_size>1024*1024
       ||flock(fd,LOCK_EX|LOCK_NB)){close(fd);return -1;}
    size_t length=(size_t)info.st_size;
    char *data=calloc(1,length+sizeof(ENTRY)+2);
    if(!data){close(fd);return -1;}
    if(read(fd,data,length)!=(ssize_t)length){free(data);close(fd);return -1;}
    if(strlen(data)!=length){free(data);close(fd);return -1;}
    char *marker,*scan=data;
    while((marker=strstr(scan,ENTRY))) {
        if(marker!=data && marker[-1]!='\n'){scan=marker+strlen(ENTRY);continue;}
        memmove(marker,marker+strlen(ENTRY),strlen(marker+strlen(ENTRY))+1);
        scan=marker;
    }
    size_t clean=strlen(data);
    if(add){
        // Do not overwrite administrator-configured entries for this hostname.
        if(strstr(data,"globaldp-prod-cn01.bhsr.com")){free(data);close(fd);return -1;}
        if(clean && data[clean-1]!='\n'){free(data);close(fd);return -1;}
        memcpy(data+clean,ENTRY,sizeof(ENTRY));
    }
    size_t updated=strlen(data);
    int result=0;
    if(updated!=length) {
        char temporary[1024];
        if(snprintf(temporary,sizeof(temporary),"%s",MGB_HOSTS_TEMP)>=(int)sizeof(temporary)){free(data);close(fd);return -1;}
        int output=mkstemp(temporary);
        struct stat current;
        if(output<0)result=-1;
        else {
            if(fchmod(output,info.st_mode&07777)||fchown(output,info.st_uid,info.st_gid)
               ||write(output,data,updated)!=(ssize_t)updated||fsync(output))result=-1;
            close(output);
            if(!result && (lstat(MGB_HOSTS_PATH,&current)||current.st_ino!=info.st_ino
                ||current.st_dev!=info.st_dev||current.st_size!=info.st_size
                ||current.st_mtimespec.tv_sec!=info.st_mtimespec.tv_sec
                ||current.st_mtimespec.tv_nsec!=info.st_mtimespec.tv_nsec))result=-1;
            if(!result && rename(temporary,MGB_HOSTS_PATH))result=-1;
            if(result)unlink(temporary);
        }
    }
    free(data);close(fd);return result;
}

static void flush_dns(void) {
#ifdef MGB_HELPER_TEST_NO_FLUSH
    return;
#else
    pid_t child=fork();
    if(child==0){execl("/usr/bin/dscacheutil","dscacheutil","-flushcache",(char *)NULL);_exit(127);}
    if(child>0){int status;while(waitpid(child,&status,0)<0 && errno==EINTR){}}
#endif
}

int main(int argc,char **argv) {
    if(argc==2 && !strcmp(argv[1],"--version")){puts("hoyobridge-startup-helper-v1");return 0;}
    if(argc!=2 || geteuid()!=MGB_HELPER_EXPECTED_EUID)return 2;
    char *end=NULL;unsigned long user=strtoul(argv[1],&end,10);
    if(!end || *end || user==0 || user>0x7fffffffUL)return 2;
    signal(SIGTERM,stop_signal);signal(SIGINT,stop_signal);signal(SIGPIPE,SIG_IGN);
    // Recover a marker left by an interrupted prior invocation at boot/restart.
    if(rewrite_hosts(0)==0)flush_dns();
    int *sockets=NULL;size_t count=0;
    if(launch_activate_socket("Requests",&sockets,&count) || count!=1){free(sockets);return 3;}
    struct pollfd descriptor={sockets[0],POLLIN,0};
    if(poll(&descriptor,1,5000)<=0){free(sockets);return 0;}
    int client=accept(sockets[0],NULL,NULL);free(sockets);
    if(client<0)return 4;
    uid_t peer;gid_t group;struct timeval timeout={3,0};
    setsockopt(client,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    if(getpeereid(client,&peer,&group)||peer!=(uid_t)user){close(client);return 0;}
    char request[6];size_t readBytes=0;
    while(readBytes<sizeof(request)){
        ssize_t n=read(client,request+readBytes,sizeof(request)-readBytes);
        if(n<=0){close(client);return 0;}readBytes+=(size_t)n;
    }
    if(memcmp(request,"START\n",6)){close(client);return 0;}
    if(rewrite_hosts(1)){write(client,"ERROR\n",6);close(client);return 0;}
    flush_dns();write(client,"READY\n",6);close(client);
    for(int i=0;i<15 && !stopping;i++)sleep(1);
    if(rewrite_hosts(0)){fprintf(stderr,"startup_marker_restore_failed\n");return 5;}
    flush_dns();return 0;
}
