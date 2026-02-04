// PXProcessKiller.h
// Small helper to kill processes without spawning a shell.

#import <Foundation/Foundation.h>
#include <signal.h>

// Best-effort kill using killall by exact process name.
// Returns YES if the command executed (not whether a process was actually killed).
BOOL PXKillallByName(NSString *processName, int signalNumber);

// Convenience helpers
BOOL PXKillallTermThenKill(NSString *processName, NSTimeInterval graceSeconds);
BOOL PXKillallTermThenKillMany(NSArray<NSString *> *processNames, NSTimeInterval graceSeconds);
