#include "fingerprint.h"
#include "wasm-rt-impl.h"
#include "wasm-rt-exceptions.h"
#include <stdio.h>
#include <math.h>
#include "include/NativeFingerprint.h"

struct w2c_a { w2c_fingerprint *module; u32 invoke; u32 function; };
static u8 *memory(struct w2c_a *host, u32 offset, size_t size) {
    wasm_rt_memory_t *mem = w2c_fingerprint_B(host->module);
    if (offset > mem->size || size > mem->size - offset) wasm_rt_trap(WASM_RT_TRAP_OOB);
    return mem->data + offset;
}
static u32 read32(struct w2c_a *host, u32 offset) {
    u32 value;
    memcpy(&value, memory(host, offset, 4), 4);
    return value;
}
void w2c_a_l(struct w2c_a *h,u32 name,u32 count,u32 args,u32 sig,u32 invoke,u32 function) {
    if (count == 2 && strcmp((char *)memory(h,name,15),"ExtractQueryFP") == 0
        && strcmp((char *)memory(h,sig,4),"iii") == 0) {
        h->invoke=invoke; h->function=function;
    }
}
u32 w2c_a_r(struct w2c_a*h,u32 to,u32 from,u32 size) { memmove(memory(h,to,size),memory(h,from,size),size);return to; }
u32 w2c_a_i(struct w2c_a*h,u32 fd,u32 vectors,u32 count,u32 output) {
    u32 total=0;for(u32 i=0;i<count;i++)total+=read32(h,vectors+i*8+4);
    memcpy(memory(h,output,4),&total,4);return 0;
}
u32 w2c_a_g(struct w2c_a*h,u32 size) { return w2c_fingerprint_E(h->module,size+16)+16; }
void w2c_a_d(struct w2c_a*h,u32 a,u32 b,u32 c,u32 d) { wasm_rt_trap(WASM_RT_TRAP_UNREACHABLE); }
void w2c_a_f(struct w2c_a*h,u32 a,u32 b,u32 c) { wasm_rt_trap(WASM_RT_TRAP_UNREACHABLE); }
void w2c_a_h(struct w2c_a*h) { wasm_rt_trap(WASM_RT_TRAP_UNREACHABLE); }
u32 w2c_a_s(struct w2c_a*h,u32 a) { return 0; }
u32 w2c_a_o(struct w2c_a*h,u32 a,u32 b) { wasm_rt_trap(WASM_RT_TRAP_UNREACHABLE);return 0; }
u32 w2c_a_t(struct w2c_a*h,u32 a,u32 b,u32 c,u32 d,u32 e) { return 0; }
u32 w2c_a_u(struct w2c_a*h,u32 a,u32 b) { return 0; }
u32 w2c_a_v(struct w2c_a*h,u32 a,u32 b) { return 0; }
void w2c_a_q(struct w2c_a*h,u32 a) { }
void w2c_a_m(struct w2c_a*h,u32 a) { }
void w2c_a_n(struct w2c_a*h,u32 a) { }
void w2c_a_A(struct w2c_a*h,u32 a,u32 b,u32 c,u32 d,u32 e,u32 f,u32 g,u32 i,u32 j,u32 k,u32 l,u32 m,u32 n) { }
void w2c_a_a(struct w2c_a*h,u32 a,u32 b,u32 c) { }
void w2c_a_b(struct w2c_a*h,u32 a,u32 b,u32 c,u32 d,u32 e) { }
void w2c_a_c(struct w2c_a*h,u32 a,u32 b,u32 c,u32 d,u32 e,u32 f,u32 g,u32 i) { }
void w2c_a_e(struct w2c_a*h,u32 a,u32 b,u32 c) { }
void w2c_a_j(struct w2c_a*h,u32 a,u32 b,u32 c) { }
void w2c_a_k(struct w2c_a*h,u32 a,u32 b) { }
void w2c_a_p(struct w2c_a*h,u32 a,u32 b,u32 c,u32 d,u32 e,u32 f,u32 g) { }
void w2c_a_w(struct w2c_a*h,u32 a,u32 b,u32 c,u32 d,u32 e,u32 f) { }
void w2c_a_x(struct w2c_a*h,u32 a,u32 b) { }
void w2c_a_y(struct w2c_a*h,u32 a,u32 b,u32 c,u32 d,u32 e) { }
void w2c_a_z(struct w2c_a*h,u32 a,u32 b) { }


int inkflow_fingerprint(const float *samples, size_t count,
                        uint8_t *output, size_t capacity, size_t *length) {
    if (!length) return -1;
    *length = 0;
    if (!samples || !output || count < 8000 || count > 96000) return -1;
    double energy = 0;
    for (size_t i = 0; i < count; i++) {
        if (!isfinite(samples[i])) return -1;
        energy += (double)samples[i] * samples[i];
    }
    // The upstream extractor fails on a silent window.
    if (energy / count < 1e-10) return 1;

    // Each call owns its complete arena, including C++ temporaries. A trapped
    // extraction cannot corrupt the following window or retain audio buffers.
    w2c_fingerprint *module = calloc(1, sizeof(*module));
    struct w2c_a *host = calloc(1, sizeof(*host));
    if (!module || !host) { free(module); free(host); return -2; }
    host->module = module;
    wasm_rt_init();
    int trap = wasm_rt_impl_try();
    if (trap != WASM_RT_TRAP_NONE) {
        wasm2c_fingerprint_free(module);
        free(module); free(host);
        return -3;
    }
    wasm2c_fingerprint_instantiate(module, host);
    w2c_fingerprint_C(module);
    wasm_rt_funcref_table_t *table = w2c_fingerprint_D(module);
    int result = -4;
    if (host->invoke && host->invoke < table->size && host->function < table->size) {
        // Emscripten's string wire format: 32-bit byte length followed by data.
        u32 size = (u32)(count * sizeof(float));
        u32 ptr = w2c_fingerprint_E(module, size + 5);
        if (!ptr) wasm_rt_trap(WASM_RT_TRAP_OOB);
        memcpy(memory(host, ptr, 4), &size, 4);
        memcpy(memory(host, ptr + 4, size), samples, size);
        *memory(host, ptr + 4 + size, 1) = 0;
        wasm_rt_funcref_t ref = table->data[host->invoke];
        u32 vector = ((u32(*)(void*,u32,u32))ref.func)(ref.module_instance, host->function, ptr);
        // vector<char> is returned inside the same 32-bit linear memory.
        u32 begin = read32(host, vector), end = read32(host, vector + 4);
        if (end >= begin && end - begin <= capacity) {
            memcpy(output, memory(host, begin, end - begin), end - begin);
            *length = end - begin;
            result = 0;
        } else { result = -5; }
    }
    wasm2c_fingerprint_free(module);
    free(module); free(host);
    return result;
}
