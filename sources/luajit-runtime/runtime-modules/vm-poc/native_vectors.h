#ifndef HD2_NATIVE_VECTORS_H
#define HD2_NATIVE_VECTORS_H
#include "native_steam.h"
/* Native engine memory access; no VM values or old Lua callbacks are reused. */
typedef HD2SteamHost HD2VectorHost;
HD2ENV_API int hd2env_probe_vector2_host(const HD2VectorHost *);
/* The native environment owns its temporary vector pool and must outlive this
 * binding. The engine's normal temporary checkpoints/frame cleanup invalidate
 * values, exactly as for original lightuserdata vectors. No pool is allocated
 * or freed by registration or HD2Environment destruction. */
HD2ENV_API int hd2env_register_vector2(HD2Environment *,const HD2VectorHost *,uintptr_t native_environment);
/* Shares the already registered Vector2 host/pool and lightuserdata metatable. */
HD2ENV_API int hd2env_register_vector3(HD2Environment *);
int hd2env_probe_vector3_host(const HD2VectorHost *);
/* Persistent boxes are owned by LuaJIT; unbox uses the native temporary pool. */
HD2ENV_API int hd2env_register_vector3box(HD2Environment *);
int hd2env_probe_vector3box_host(const HD2VectorHost *);
HD2ENV_API int hd2env_register_vector4(HD2Environment *);
int hd2env_probe_vector4_host(const HD2VectorHost *);
/* Shares the Vector4 payload; requires Vector4. See quaternion.inc for fitted and pending entries. */
HD2ENV_API int hd2env_register_quaternion(HD2Environment *);
int hd2env_probe_quaternion_host(const HD2VectorHost *);
/* Witness-checked calls into the game's own pure math helpers; 0 if refused. */
int hd2quaternion_atan2f(const HD2VectorHost *,float y,float x,float *);
int hd2quaternion_asinf(const HD2VectorHost *,float,float *);
int hd2quaternion_acosf(const HD2VectorHost *,float,float *);
int hd2quaternion_sinf(const HD2VectorHost *,float,float *);
int hd2quaternion_from_euler(const HD2VectorHost *,const float degrees[3],float out[4]);
int hd2quaternion_from_basis(const HD2VectorHost *,const float matrix[16],float out[4]);
/* Matrix4x4 (tag 0x7fd2e074, 16 row-major floats) shares the temporary pool
 * and LightUserData metatable; requires Quaternion. Also completes
 * Quaternion.matrix4x4/from_matrix4x4. See matrix4x4.inc for pending entries. */
HD2ENV_API int hd2env_register_matrix4x4(HD2Environment *);
int hd2env_probe_matrix4x4_host(const HD2VectorHost *);
/* QuaternionBox and Matrix4x4Box (LuaJIT-owned 16/64-byte payloads); requires Matrix4x4. */
HD2ENV_API int hd2env_register_boxes(HD2Environment *);
uintptr_t hd2matrix4x4_allocate(const HD2VectorHost *,uintptr_t native_environment);
int hd2matrix4x4_inverse(const HD2VectorHost *,const float in[16],float out[16]);
int hd2matrix4x4_rotation(const HD2VectorHost *,const float in[16],float out[4]);
int hd2vector2_pool_valid(const HD2VectorHost *,uintptr_t native_environment);
uintptr_t hd2vector2_allocate(const HD2VectorHost *,uintptr_t native_environment);
uintptr_t hd2vector3_allocate(const HD2VectorHost *,uintptr_t native_environment);
uintptr_t hd2vector4_allocate(const HD2VectorHost *,uintptr_t native_environment);
int hd2vector2_format(const HD2VectorHost *,char *,float,float);
int hd2vector3_format(const HD2VectorHost *,char *,float,float,float);
int hd2vector4_format(const HD2VectorHost *,char *,float,float,float,float);
/* One float with the engine formatter (%.9g, engine NaN spelling); out >= 64 bytes. */
int hd2vector_format_float(const HD2VectorHost *,char *,float);
int hd2vector_temp_count(const HD2VectorHost *,uintptr_t,uint32_t *);
int hd2vector_temp_restore(const HD2VectorHost *,uintptr_t,uint32_t);
/* Frees native overflow pages and invalidates the inline ring before each
 * update/render. The native pointer array stays owned by its environment. */
int hd2vector_temp_clear(const HD2VectorHost *,uintptr_t);
#endif
