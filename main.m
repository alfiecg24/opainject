#import <stdio.h>
#import <stdlib.h>
#import <unistd.h>
#import <dlfcn.h>
#import <mach-o/getsect.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <mach-o/reloc.h>
#import <sys/utsname.h>
#import <string.h>
#import <limits.h>
#import <spawn.h>
#import "dyld.h"
#import <CoreFoundation/CoreFoundation.h>
#import "rop_inject.h"


char* resolvePath(char* pathToResolve)
{
	if(strlen(pathToResolve) == 0) return NULL;
	if(pathToResolve[0] == '/')
	{
		return strdup(pathToResolve);
	}
	else
	{
		char absolutePath[PATH_MAX];
		if (realpath(pathToResolve, absolutePath) == NULL) {
			perror("[resolvePath] realpath");
			return NULL;
		}
		return strdup(absolutePath);
	}
}

int main(int argc, char *argv[], char *envp[]) {
	@autoreleasepool
	{
		setlinebuf(stdout);
		setlinebuf(stderr);
		if (argc < 3 || argc > 4)
		{
			printf("Usage: opainject <pid> <path/to/dylib>\n");
			return -1;
		}

		printf("OPAINJECT HERE WE ARE\n");
		printf("RUNNING AS %d\n", getuid());

		pid_t targetPid = atoi(argv[1]);
		kern_return_t kret = 0;
		task_t procTask = MACH_PORT_NULL;
		char* dylibPath = resolvePath(argv[2]);
		if(!dylibPath) return -3;
		if(access(dylibPath, R_OK) < 0)
		{
			printf("ERROR: Can't access passed dylib at %s\n", dylibPath);
			return -4;
		}

		// get task port
		kret = task_for_pid(mach_task_self(), targetPid, &procTask);
		if(kret != KERN_SUCCESS)
		{
			printf("ERROR: task_for_pid failed with error code %d (%s)\n", kret, mach_error_string(kret));
			return -2;
		}
		if(!MACH_PORT_VALID(procTask))
		{
			printf("ERROR: Got invalid task port (%d)\n", procTask);
			return -3;
		}

		printf("Got task port %d for pid %d!\n", procTask, targetPid);

		// get aslr slide
		task_dyld_info_data_t dyldInfo;
		uint32_t count = TASK_DYLD_INFO_COUNT;
		task_info(procTask, TASK_DYLD_INFO, (task_info_t)&dyldInfo, &count);

		injectDylibViaRop(procTask, targetPid, dylibPath, dyldInfo.all_image_info_addr);

		mach_port_deallocate(mach_task_self(), procTask);
		
		return 0;
	}
}
