+++
title = "Windows service programs with Zig"
date = "2024-09-25"
+++

# Introduction

This post will demonstrate a basic [Windows
service](https://learn.microsoft.com/en-us/windows/win32/services/services)
implementation using Zig.

# Windows APIs

In order to get access to the Windows APIs, we need to tell our application
about the functions. To do this we can declare `extern` functions. For example,
the
[`GetAdaptersAddresses`](https://learn.microsoft.com/en-us/windows/win32/api/iphlpapi/nf-iphlpapi-getadaptersaddresses)
function.

```zig
extern fn GetAdaptersAddresses(u32, u32, ?*anyopaque, ?*IP_ADAPTER_ADDRESSES, ?*u32) callconv (@import("std").os.windows.WINAPI) u32;
```

Not so bad, right?

Oops I almost forgot:
[`IP_ADAPTER_ADDRESSES`](https://learn.microsoft.com/en-us/windows/win32/api/iptypes/ns-iptypes-ip_adapter_addresses_lh)
isn't defined yet. Let's add this real quick... Ok, maybe not - that's a lot of
fields and a lot of typing.

Thankfully, [Jonathan Marler](https://github.com/marler8997) created a binding
generator appropriately named
[zigwin32](https://github.com/marlersoft/zigwin32) that generates Zig bindings
for Win32. We can fetch zigwin32 with Zig's built-in package manager and make
it available to our `build.zig` script.

```shell
zig fetch --save 'git+https://github.com/marlersoft/zigwin32#main'
```

After adding it to our `exe`'s `root_module`, we can continue.

# `main.zig` Skeleton

For a starting point, we'll create three functions: `main`, `serviceMain`, and
`serviceControl`.

Our `main` function is our entry point to our application. No surprises here.
The `serviceMain` and `serviceControl` functions will be called by the service
control manager. We'll get into the details of these functions a bit later, but
take note of their signatures and calling conventions.

```zig
pub fn main() void {
}

pub fn serviceMain(argc: u32, argv: ?*?[*:0]const u8) callconv(std.os.windows.WINAPI) void {
}

pub fn serviceControl(
    code: u32,
    event_type: u32,
    event_data: ?*anyopaque,
    context: ?*anyopaque,
) callconv(std.os.windows.WINAPI) u32 {
}

const std = @import("std");
const win32 = @import("win32");
```

# Connect to the service control manager

Our service program may run several different services within one process. We
can define the services that run within our process as a [service
table](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/ns-winsvc-service_table_entrya).
Each entry in this table contains a string holding the service name and a
function pointer that points to the service's entry point. In this case, it's
our `serviceMain` function. Let's define the service table in our main function.

```zig
const service_name = "My Awesome Service";

pub fn main() void {
    const service_table = [_]win32.system.services.SERVICE_TABLE_ENTRYA{
        .{
            .lpServiceName = @constCast(service_name.ptr),
            .lpServiceProc = serviceMain,
        },
        .{ .lpServiceName = null, .lpServiceProc = null },
    };
}
```

After we define the services our process will run, we need to connect our
service program to the service control manager and tell it about our services.
We do this by calling
[`StartServiceCtrlDispatcherA`](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/nf-winsvc-startservicectrldispatchera),
passing the table we created in the previous step.

```zig
pub fn main() void {
    // -- snip --

    if (win32.system.services.StartServiceCtrlDispatcherA(&service_table[0]) > 0) {
        // error
    }
}
```

Note that the call to `StartServiceCtrlDispatcherA` doesn't return until all
services within our service table are stopped, so we can just return after this
call. It is possible this function doesn't return for a very long time!

# Initialize the service

After calling `StartServiceCtrlDispatcherA` and creating the connection, the
service control manager will call our `serviceMain` function we registered in
the table earlier.

Once we enter `serviceMain`, the service control manager needs to send events to
our service. For example, in the services console in Windows, right-clicking a
service displays a menu with some actions: Start, Stop, Pause, Restart, etc.
These are all events that our service needs to handle. But before we handle
anything, we need to tell the service control manager where to send its events.
This is where the `serviceControl` function comes in.

## Registering the control handler

Inside our `serviceMain` function we'll register the `serviceControl` function
with the service control manager, telling it to call this function when an
event is generated. We do this with the
[`RegisterServiceCtrlHandlerExA`](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/nf-winsvc-registerservicectrlhandlerexa)
function.

```zig
pub fn serviceMain(argc: u32, argv: ?*?[*:0]const u8) callconv(std.os.windows.WINAPI) void {
    const status_handle = win32.system.services.RegisterServiceCtrlHandlerExA(service_name.ptr, serviceControl, null);
    if (status_handle == 0) {
        // error
        return;
    }
}
```

This call returns a handle that we'll also need in `serviceControl`, so let's save the handle to the `status_handle` variable.

## Passing data between functions

Since `serviceMain` doesn't directly call `serviceControl`, we need some way of
sharing data between these two functions. One way is to create global variables
that the two functions can access. However, I really don't like global data,
and try avoid it as much as possible.

You'll note that in the previous section I chose to register our
`serviceControl` function via `RegisterServiceCtrlHandlerExA` instead of
`RegisterServiceCtrlHandlerA`. This was intentional. The former allows us to
pass in a pointer that gets forwarded to `serviceMain`.

Let's create a simple `ServiceData` struct that we can provide to the control registration.

```zig
const ServiceData = struct {
    handle: isize = -1,
    status: win32.system.services.SERVICE_STATUS = .{
        .dwServiceType = win32.system.services.SERVICE_WIN32_OWN_PROCESS,
        .dwCurrentState = .START_PENDING,
        .dwControlsAccepted = 0,
        .dwWin32ExitCode = 0,
        .dwServiceSpecificExitCode = 0,
        .dwCheckPoint = 0,
        .dwWaitHint = 0,
    },
    stop_event: ?*anyopaque = null,
};
```

Don't worry too much about these fields for now, we'll get to them later.

## Thread synchronization

I hope I didn't scare you too badly with that section title, it's not that bad, I promise.

Our process needs to stay open as long as our services are running. If we
return from `serviceMain`, our process closes and we lose our services. This is
not what we want. You might be tempted to put a `while (true) {}` block at the
end of `serviceMain` but that has its own problems I won't get into here.

Instead, we'll create a waitable event using with
[`CreateEventA`](https://learn.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-createeventa).
This function will create a synchronization primitive that we can use as a
signaling mechanism to block the main thread until something happens. For now,
let's save this event object to the `stop_event` variable.

```zig
pub fn serviceMain(argc: u32, argv: ?*?[*:0]const u8) callconv(std.os.windows.WINAPI) void {
    // -- snip --

    const stop_event = win32.system.threading.CreateEventA(null, 0, 1, null);
    if (stop_event == null) {
        // error
        return;
    }
}
```

## Up and running {#up-and-running}

We now have everything we need to tell the service control manager we're running
and ready to handle events. Let's initialize a `ServiceData` struct to hold the
data we created in the previous steps.

```zig
pub fn serviceMain(argc: u32, argv: ?*?[*:0]const u8) callconv(std.os.windows.WINAPI) void {
    // -- snip --

    var service_data = ServiceData{
        .handle = status_handle.
        .stop_event = stop_event,
    };
}
```

Next, let's set our `ServiceData` state to running and tell the service control
manager we'll handle stop and shutdown commands. We'll do this by updating the
`dwCurrentState` and `dwControlsAccepted` fields in the  `ServiceData.status`
we just initialized. Then, we'll update the service control manager with this
new data with the
[`SetServiceStatus`](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/nf-winsvc-setservicestatus)
function.

```zig
pub fn serviceMain(argc: u32, argv: ?*?[*:0]const u8) callconv(std.os.windows.WINAPI) void {
    // -- snip --

    service_data.status.dwCurrentState = .RUNNING;
    service_data.status.dwControlsAccepted = win32.system.services.SERVICE_CONTROL_STOP | win32.system.services.SERVICE_CONTROL_SHUTDOWN;
    if (services.SetServiceStatus(service_data.handle, &service_data.status) == 0) {
        // error
    }
}
```

Finally, we'll await a signal from the `stop_event` we created earlier to block
the process using
[`WaitForSingleObject`](https://learn.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-waitforsingleobject).
Since this call is blocks until we signal the `stop_event` object, we can
assume if we get past this our service was stopped and we can update our status
with the service control manager.

```zig
pub fn serviceMain(argc: u32, argv: ?*?[*:0]const u8) callconv(std.os.windows.WINAPI) void {
    // -- snip --

    if (win32.system.threading.WaitForSingleObject(service_data.stop_event, win32.system.windows_programming.INFINITE) != 0) {
        // error
        return;
    }

    service_data.status.dwCurrentState = .STOPPED;
    if (services.SetServiceStatus(service_data.handle, &service_data.status) != 0) {
        // error
    }
```

# Handling events

Now that we've initialized our service and are blocking the process waiting for
events, we can get implement the `serviceControl` function that handles these
events.

We can retrieve our `service_data` pointer we passed previously by casting it
to our `ServiceData` type. Also, we'll switch on the `code`, which is the event
sent to us by the service control manager. Our service is pretty dumb, so we
won't have a lot of robust handling here. For now, we'll just return
`NO_ERROR`.

```zig
pub fn serviceControl(
    code: u32,
    event_type: u32,
    event_data: ?*anyopaque,
    context: ?*anyopaque,
) callconv(std.os.windows.WINAPI) u32 {
    var service_data: *ServiceData = @alignCast(@ptrCast(context.?));

    const err: win32.foundation.WIN32_ERROR = switch (code) {
        else => .NO_ERROR,
    };

    return @intFromEnum(err);
}
```

The [control handler
documentation](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/nc-winsvc-lphandler_function_ex)
says that we should return `ERROR_CALL_NOT_IMPLEMENTED` if we don't handle an
event, and `NO_ERROR` for the `SERVICE_CONTROL_INTERROGATE`, event if we don't
handle it.

```zig
    // -- snip --

    const err: win32.foundation.WIN32_ERROR = switch (code) {
        win32.system.services.SERVICE_CONTROL_INTERROGATE => .NO_ERROR,
        else => .ERROR_CALL_NOT_IMPLEMENTED,
    };

    // -- snip --
```

Next, we'll handle the stop and shutdown events. When we handle these, we'll
need to make sure deinitialization happens properly either here in our control
handler or `serviceMain`. Remember, in the [Up and running](#up-and-running)
section we created and awaited our stop event which is blocking our process. If
we never signaled the object, the process would never terminate. In order to
signal the event object, we'll use the
[`SetEvent`](https://learn.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-setevent)
function.

```zig
    // -- snip --

    const err: win32.foundation.WIN32_ERROR = switch (code) {
        win32.system.services.SERVICE_CONTROL_STOP, win32.system.services.SERVICE_CONTROL_SHUTDOWN => blk: {
            service_data.status.dwCurrentState = .STOP_PENDING;
            if (win32.system.services.SetServiceStatus(service_data.handle, &service_data.status) == 0) {
                // error
            }
            if (win32.system.threading.SetEvent(service_data.stop_event) == 0) {
                // error
            }
            break :blk .NO_ERROR;
        },

        // -- snip --
    };

    // -- snip --
```

# Wrap up

I hope this post was helpful in showing how to use Zig to create Windows
services. I just did the bare minimum here, but there's so much room for
improvement, starting with refactoring this code to read more like idiomatic
Zig code.

It's also nearly impossible to diagnose crashes. Logging would be a great
addition as well.

Although our service can be started, stopped, and restarted, doesn't really do
anything. That's neither practical nor useful. However, the possibilities are
endless. Here are some examples:
- File monitoring
- Data backup
- Content synchronization
- Web APIs
- Notifications

# Full example

```zig
const service_name = "My Awesome Service";

pub fn main() void {
    const service_table = [_]win32.system.services.SERVICE_TABLE_ENTRYA{
        .{
            .lpServiceName = @constCast(service_name.ptr),
            .lpServiceProc = serviceMain,
        },
        .{ .lpServiceName = null, .lpServiceProc = null },
    };

    if (win32.system.services.StartServiceCtrlDispatcherA(&service_table[0]) > 0) {
        // error
    }
}

pub fn serviceMain(argc: u32, argv: ?*?[*:0]const u8) callconv(std.os.windows.WINAPI) void {
    _ = argc;
    _ = argv;

    const status_handle = win32.system.services.RegisterServiceCtrlHandlerExA(service_name.ptr, serviceControl, null);
    if (status_handle == 0) {
        // error
        return;
    }

    const stop_event = win32.system.threading.CreateEventA(null, 0, 1, null);
    if (stop_event == null) {
        // error
        return;
    }

    var service_data = ServiceData{
        .handle = status_handle.
        .stop_event = stop_event,
    };

    service_data.status.dwCurrentState = .RUNNING;
    service_data.status.dwControlsAccepted = win32.system.services.SERVICE_CONTROL_STOP | win32.system.services.SERVICE_CONTROL_SHUTDOWN;
    if (services.SetServiceStatus(service_data.handle, &service_data.status) == 0) {
        // error
    }

    if (win32.system.threading.WaitForSingleObject(service_data.stop_event, win32.system.windows_programming.INFINITE) != 0) {
        // error
        return;
    }

    service_data.status.dwCurrentState = .STOPPED;
    if (services.SetServiceStatus(service_data.handle, &service_data.status) != 0) {
        // error
    }
}

pub fn serviceControl(
    code: u32,
    event_type: u32,
    event_data: ?*anyopaque,
    context: ?*anyopaque,
) callconv(std.os.windows.WINAPI) u32 {
    _ = event_type;
    _ = event_data;

    var service_data: *ServiceData = @alignCast(@ptrCast(context.?));

    const err: win32.foundation.WIN32_ERROR = switch (code) {
        win32.system.services.SERVICE_CONTROL_STOP, win32.system.services.SERVICE_CONTROL_SHUTDOWN => blk: {
            service_data.status.dwCurrentState = .STOP_PENDING;
            if (win32.system.services.SetServiceStatus(service_data.handle, &service_data.status) == 0) {
                // error
            }
            if (win32.system.threading.SetEvent(service_data.stop_event) == 0) {
                // error
            }
            break :blk .NO_ERROR;
        },
        win32.system.services.SERVICE_CONTROL_INTERROGATE => .NO_ERROR,
        else => .ERROR_CALL_NOT_IMPLEMENTED,
    };

    return @intFromEnum(err);
}

const std = @import("std");
const win32 = @import("win32");
const ServiceData = struct {
    handle: isize = -1,
    status: win32.system.services.SERVICE_STATUS = .{
        .dwServiceType = win32.system.services.SERVICE_WIN32_OWN_PROCESS,
        .dwCurrentState = .START_PENDING,
        .dwControlsAccepted = 0,
        .dwWin32ExitCode = 0,
        .dwServiceSpecificExitCode = 0,
        .dwCheckPoint = 0,
        .dwWaitHint = 0,
    },
    stop_event: ?*anyopaque = null,
};
