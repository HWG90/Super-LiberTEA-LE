#pragma once
// Proton represents mapped PE sections as MEM_MAPPED, and writable data as
// PAGE_WRITECOPY. Keep build, allocation owner and exact dispatch-slot checks.
static bool wine_section_mapping(const MEMORY_BASIC_INFORMATION& r) {
    static const bool wine=GetProcAddress(GetModuleHandleW(L"ntdll.dll"),"wine_get_version")!=nullptr;
    return wine && r.Type==MEM_MAPPED;
}
static bool pe_section_mapping(const MEMORY_BASIC_INFORMATION& r) {
    return r.Type==MEM_IMAGE || wine_section_mapping(r);
}
static bool writable_pe_protection(DWORD protection) {
    return protection==PAGE_READWRITE || protection==PAGE_WRITECOPY;
}
