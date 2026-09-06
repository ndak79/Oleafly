#define INITGUID

#include <stddef.h>
#include <stdint.h>

#include <d3d11.h>
#include <dxgi1_5.h>
#include <dwmapi.h>
#include <wincodec.h>

/* mingw-w64 keeps this interface IID as an external declaration even with
 * INITGUID; define the SDK-declared value in this probe translation unit. */
const IID IID_IWICImagingFactory = {
    0xec5ec8a9,
    0xc395,
    0x4314,
    { 0x9c, 0x77, 0x54, 0xd7, 0xa9, 0x35, 0xff, 0x70 },
};

_Static_assert(sizeof(void *) == 8, "the SDK probe is x64-only");
_Static_assert(sizeof(GUID) == 16, "GUID layout changed");
_Static_assert(sizeof(DXGI_FORMAT) == 4, "DXGI_FORMAT layout changed");
_Static_assert(sizeof(IDXGIOutput5) == sizeof(void *), "IDXGIOutput5 must be one vtable pointer");
_Static_assert(offsetof(IDXGIOutput5Vtbl, DuplicateOutput1) == 26 * sizeof(void *), "IDXGIOutput5 vtable slot changed");
_Static_assert(sizeof(IDXGIOutputDuplication) == sizeof(void *), "IDXGIOutputDuplication must be one vtable pointer");
_Static_assert(sizeof(IWICImagingFactory) == sizeof(void *), "IWICImagingFactory must be one vtable pointer");
_Static_assert(offsetof(IWICImagingFactoryVtbl, CreateEncoder) == 8 * sizeof(void *), "IWICImagingFactory vtable slot changed");
_Static_assert(sizeof(IWICBitmapEncoder) == sizeof(void *), "IWICBitmapEncoder must be one vtable pointer");
_Static_assert(offsetof(IWICBitmapEncoderVtbl, Initialize) == 3 * sizeof(void *), "IWICBitmapEncoder vtable slot changed");
_Static_assert(DWMWA_EXTENDED_FRAME_BOUNDS == 9, "DWM attribute value changed");
_Static_assert(D3D11_SDK_VERSION == 7, "D3D11 SDK version changed");
_Static_assert(D3D11_CREATE_DEVICE_BGRA_SUPPORT == 0x20, "D3D11 BGRA creation flag changed");
_Static_assert(sizeof(ID3D11Device) == sizeof(void *), "ID3D11Device must be one vtable pointer");
_Static_assert(offsetof(ID3D11DeviceVtbl, CreateBuffer) == 3 * sizeof(void *), "ID3D11Device vtable slot changed");

#define TEXFLOW_EXPORT __declspec(dllexport)

TEXFLOW_EXPORT uint32_t texflow_sdk_dxgi_output5_duplicate_output1_slot(void) {
    return (uint32_t)(offsetof(IDXGIOutput5Vtbl, DuplicateOutput1) / sizeof(void *));
}

TEXFLOW_EXPORT uint32_t texflow_sdk_dxgi_output_duplication_size(void) {
    return (uint32_t)sizeof(IDXGIOutputDuplication);
}

TEXFLOW_EXPORT uint32_t texflow_sdk_wic_factory_create_encoder_slot(void) {
    return (uint32_t)(offsetof(IWICImagingFactoryVtbl, CreateEncoder) / sizeof(void *));
}

TEXFLOW_EXPORT uint32_t texflow_sdk_wic_encoder_initialize_slot(void) {
    return (uint32_t)(offsetof(IWICBitmapEncoderVtbl, Initialize) / sizeof(void *));
}

TEXFLOW_EXPORT uint32_t texflow_sdk_dxgi_format_b8g8r8a8_unorm(void) {
    return (uint32_t)DXGI_FORMAT_B8G8R8A8_UNORM;
}

TEXFLOW_EXPORT uint32_t texflow_sdk_dwm_extended_frame_bounds(void) {
    return (uint32_t)DWMWA_EXTENDED_FRAME_BOUNDS;
}

TEXFLOW_EXPORT uint32_t texflow_sdk_d3d11_sdk_version(void) { return (uint32_t)D3D11_SDK_VERSION; }
TEXFLOW_EXPORT uint32_t texflow_sdk_d3d11_bgra_support_flag(void) { return (uint32_t)D3D11_CREATE_DEVICE_BGRA_SUPPORT; }
TEXFLOW_EXPORT uint32_t texflow_sdk_d3d11_device_size(void) { return (uint32_t)sizeof(ID3D11Device); }
TEXFLOW_EXPORT uint32_t texflow_sdk_d3d11_device_create_buffer_slot(void) { return (uint32_t)(offsetof(ID3D11DeviceVtbl, CreateBuffer) / sizeof(void *)); }

TEXFLOW_EXPORT uint32_t texflow_sdk_iid_idxgioutput5_data1(void) { return IID_IDXGIOutput5.Data1; }
TEXFLOW_EXPORT uint32_t texflow_sdk_iid_idxgioutput5_data2(void) { return IID_IDXGIOutput5.Data2; }
TEXFLOW_EXPORT uint32_t texflow_sdk_iid_idxgioutput5_data3(void) { return IID_IDXGIOutput5.Data3; }
TEXFLOW_EXPORT uint32_t texflow_sdk_iid_idxgioutput5_data4(void) { return IID_IDXGIOutput5.Data4[0] | ((uint32_t)IID_IDXGIOutput5.Data4[1] << 8) | ((uint32_t)IID_IDXGIOutput5.Data4[2] << 16) | ((uint32_t)IID_IDXGIOutput5.Data4[3] << 24); }
TEXFLOW_EXPORT uint32_t texflow_sdk_iid_idxgioutput5_data4_hi(void) { return IID_IDXGIOutput5.Data4[4] | ((uint32_t)IID_IDXGIOutput5.Data4[5] << 8) | ((uint32_t)IID_IDXGIOutput5.Data4[6] << 16) | ((uint32_t)IID_IDXGIOutput5.Data4[7] << 24); }

TEXFLOW_EXPORT uint32_t texflow_sdk_iid_wic_factory_data1(void) { return IID_IWICImagingFactory.Data1; }
TEXFLOW_EXPORT uint32_t texflow_sdk_iid_wic_factory_data2(void) { return IID_IWICImagingFactory.Data2; }
TEXFLOW_EXPORT uint32_t texflow_sdk_iid_wic_factory_data3(void) { return IID_IWICImagingFactory.Data3; }
TEXFLOW_EXPORT uint32_t texflow_sdk_iid_wic_factory_data4(void) { return IID_IWICImagingFactory.Data4[0] | ((uint32_t)IID_IWICImagingFactory.Data4[1] << 8) | ((uint32_t)IID_IWICImagingFactory.Data4[2] << 16) | ((uint32_t)IID_IWICImagingFactory.Data4[3] << 24); }
TEXFLOW_EXPORT uint32_t texflow_sdk_iid_wic_factory_data4_hi(void) { return IID_IWICImagingFactory.Data4[4] | ((uint32_t)IID_IWICImagingFactory.Data4[5] << 8) | ((uint32_t)IID_IWICImagingFactory.Data4[6] << 16) | ((uint32_t)IID_IWICImagingFactory.Data4[7] << 24); }

TEXFLOW_EXPORT uint32_t texflow_sdk_png_guid_data1(void) { return GUID_ContainerFormatPng.Data1; }
TEXFLOW_EXPORT uint32_t texflow_sdk_png_guid_data2(void) { return GUID_ContainerFormatPng.Data2; }
TEXFLOW_EXPORT uint32_t texflow_sdk_png_guid_data3(void) { return GUID_ContainerFormatPng.Data3; }
TEXFLOW_EXPORT uint32_t texflow_sdk_png_guid_data4(void) { return GUID_ContainerFormatPng.Data4[0] | ((uint32_t)GUID_ContainerFormatPng.Data4[1] << 8) | ((uint32_t)GUID_ContainerFormatPng.Data4[2] << 16) | ((uint32_t)GUID_ContainerFormatPng.Data4[3] << 24); }
TEXFLOW_EXPORT uint32_t texflow_sdk_png_guid_data4_hi(void) { return GUID_ContainerFormatPng.Data4[4] | ((uint32_t)GUID_ContainerFormatPng.Data4[5] << 8) | ((uint32_t)GUID_ContainerFormatPng.Data4[6] << 16) | ((uint32_t)GUID_ContainerFormatPng.Data4[7] << 24); }

TEXFLOW_EXPORT uint32_t texflow_sdk_bgra_guid_data1(void) { return GUID_WICPixelFormat32bppBGRA.Data1; }
TEXFLOW_EXPORT uint32_t texflow_sdk_bgra_guid_data2(void) { return GUID_WICPixelFormat32bppBGRA.Data2; }
TEXFLOW_EXPORT uint32_t texflow_sdk_bgra_guid_data3(void) { return GUID_WICPixelFormat32bppBGRA.Data3; }
TEXFLOW_EXPORT uint32_t texflow_sdk_bgra_guid_data4(void) { return GUID_WICPixelFormat32bppBGRA.Data4[0] | ((uint32_t)GUID_WICPixelFormat32bppBGRA.Data4[1] << 8) | ((uint32_t)GUID_WICPixelFormat32bppBGRA.Data4[2] << 16) | ((uint32_t)GUID_WICPixelFormat32bppBGRA.Data4[3] << 24); }
TEXFLOW_EXPORT uint32_t texflow_sdk_bgra_guid_data4_hi(void) { return GUID_WICPixelFormat32bppBGRA.Data4[4] | ((uint32_t)GUID_WICPixelFormat32bppBGRA.Data4[5] << 8) | ((uint32_t)GUID_WICPixelFormat32bppBGRA.Data4[6] << 16) | ((uint32_t)GUID_WICPixelFormat32bppBGRA.Data4[7] << 24); }

TEXFLOW_EXPORT uint32_t texflow_sdk_iid_d3d11_device_data1(void) { return IID_ID3D11Device.Data1; }
TEXFLOW_EXPORT uint32_t texflow_sdk_iid_d3d11_device_data2(void) { return IID_ID3D11Device.Data2; }
TEXFLOW_EXPORT uint32_t texflow_sdk_iid_d3d11_device_data3(void) { return IID_ID3D11Device.Data3; }
TEXFLOW_EXPORT uint32_t texflow_sdk_iid_d3d11_device_data4(void) { return IID_ID3D11Device.Data4[0] | ((uint32_t)IID_ID3D11Device.Data4[1] << 8) | ((uint32_t)IID_ID3D11Device.Data4[2] << 16) | ((uint32_t)IID_ID3D11Device.Data4[3] << 24); }
TEXFLOW_EXPORT uint32_t texflow_sdk_iid_d3d11_device_data4_hi(void) { return IID_ID3D11Device.Data4[4] | ((uint32_t)IID_ID3D11Device.Data4[5] << 8) | ((uint32_t)IID_ID3D11Device.Data4[6] << 16) | ((uint32_t)IID_ID3D11Device.Data4[7] << 24); }
