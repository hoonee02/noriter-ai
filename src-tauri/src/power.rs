//! Background/foreground process priority control (Windows only).
//!
//! When the window is hidden (closed to tray), there's no reason for this
//! process to compete for CPU at normal priority -- only the Telegram
//! long-poll loop and any in-flight Ollama request are running, both
//! I/O-bound. Lowering to IDLE priority while hidden and restoring NORMAL
//! on show costs nothing when the machine is idle and avoids contending
//! with foreground apps when it isn't.

#[cfg(windows)]
pub fn set_background(background: bool) {
    use windows_sys::Win32::System::Threading::{
        GetCurrentProcess, SetPriorityClass, IDLE_PRIORITY_CLASS, NORMAL_PRIORITY_CLASS,
    };
    let class = if background { IDLE_PRIORITY_CLASS } else { NORMAL_PRIORITY_CLASS };
    unsafe {
        SetPriorityClass(GetCurrentProcess(), class);
    }
}

#[cfg(not(windows))]
pub fn set_background(_background: bool) {}
