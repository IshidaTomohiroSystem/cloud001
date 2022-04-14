Shader "FullScreen/EllipseCloud"
{
    HLSLINCLUDE

    #pragma vertex Vert

    #pragma target 4.5
    #pragma only_renderers d3d11 playstation xboxone xboxseries vulkan metal switch

    #include "Packages/com.unity.render-pipelines.high-definition/Runtime/RenderPipeline/RenderPass/CustomPass/CustomPassCommon.hlsl"

    // The PositionInputs struct allow you to retrieve a lot of useful information for your fullScreenShader:
    // struct PositionInputs
    // {
    //     float3 positionWS;  // World space position (could be camera-relative)
    //     float2 positionNDC; // Normalized screen coordinates within the viewport    : [0, 1) (with the half-pixel offset)
    //     uint2  positionSS;  // Screen space pixel coordinates                       : [0, NumPixels)
    //     uint2  tileCoord;   // Screen tile coordinates                              : [0, NumTiles)
    //     float  deviceDepth; // Depth from the depth buffer                          : [0, 1] (typically reversed)
    //     float  linearDepth; // View space Z coordinate                              : [Near, Far]
    // };

    // To sample custom buffers, you have access to these functions:
    // But be careful, on most platforms you can't sample to the bound color buffer. It means that you
    // can't use the SampleCustomColor when the pass color buffer is set to custom (and same for camera the buffer).
    // float4 SampleCustomColor(float2 uv);
    // float4 LoadCustomColor(uint2 pixelCoords);
    // float LoadCustomDepth(uint2 pixelCoords);
    // float SampleCustomDepth(float2 uv);

    // There are also a lot of utility function you can use inside Common.hlsl and Color.hlsl,
    // you can check them out in the source code of the core SRP package.

    static float3x3 matOffset = float3x3(
        float3(0, 0.8, 0.16),
        float3(-0.8, 0.36, -0.418),
        float3(-0.6, -0.48, 0.164)
    );

    float Hash(float number)
    {
        return frac(sin(number) * 43758.5453);
    }

    float Noise(in float3 number)
    {
        float3 p = floor(number);
        float3 f = frac(number);

        f = f * f * (3.0 - 2.0 * f);
        float n = p.x + p.y * 57.0 + 113.0 * p.z;

        float res = lerp(lerp(lerp(Hash(n + 0.0), Hash(n + 1.0), f.x),
            lerp(Hash(n + 57.0), Hash(n + 58.0), f.x), f.y),
            lerp(lerp(Hash(n + 113.0), Hash(n + 114.0), f.x),
                lerp(Hash(n + 170.0), Hash(n + 171.0), f.x), f.y), f.z);
        return res;
    }

    // Fractal Brownian motion
    float Fbm(float3 p)
    {
        float f;
        f = 0.5000 * Noise(p); p = mul(matOffset, p) * 2.02;
        f += 0.2500 * Noise(p); p = mul(matOffset, p) * 2.03;
        f += 0.250 * Noise(p);
        return f;
    }

    float DistEllipse(float3 rayOrigin, float3 ellipsePoint)
    {
        float p = (rayOrigin.x * rayOrigin.x) / (ellipsePoint.x * ellipsePoint.x) +
            (rayOrigin.y * rayOrigin.y) / (ellipsePoint.y * ellipsePoint.y) +
            (rayOrigin.z * rayOrigin.z) / (ellipsePoint.z * ellipsePoint.z) - 1;
        return p;
    }

    float EllipseCloudDens(float3 rayOrigin, float3 ellipsePoint)
    {
        return 0.1 - DistEllipse(rayOrigin, ellipsePoint) * 0.5 + Fbm(rayOrigin * 0.3);
    }

    float4 FullScreenPass(Varyings varyings) : SV_Target
    {
        UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(varyings);
        float depth = LoadCameraDepth(varyings.positionCS.xy);
        PositionInputs posInput = GetPositionInput(varyings.positionCS.xy, _ScreenSize.zw, depth, UNITY_MATRIX_I_VP, UNITY_MATRIX_V);
        float3 viewDirection = GetWorldSpaceNormalizeViewDir(posInput.positionWS);
        float4 color = float4(0.0, 0.0, 0.0, 0.0);

        // Load the camera color buffer at the mip 0 if we're not at the before rendering injection point
        if (_CustomPassInjectionPoint != CUSTOMPASSINJECTIONPOINT_BEFORE_RENDERING)
            color = float4(CustomPassLoadCameraColor(varyings.positionCS.xy, 0), 1);

        float4 originColor = color;

        // Add your custom pass code here
        float3 rayOrigin = _WorldSpaceCameraPos;
        float3 rayDir = normalize(posInput.positionWS);
        float3 pos = posInput.positionWS;
        
        int sampleCount = 128;

        // ray marching step settings
        float zMax = 100.0;

        float zStep = zMax / float(sampleCount);
        float transmittance = 1.0;
        float absorption = 50.0;

        for (int i = 0; i < sampleCount; i++)
        {
            float dens = EllipseCloudDens(rayOrigin, float3(4, 2, 2));
            int densValue = (dens > 0.0) ? 1 : 0;

            transmittance = (dens > 0.0) ? transmittance * (1.0 - ((dens / float(sampleCount)) * absorption)) : transmittance;
            int transmittanceValue = (transmittance <= 0.01) ? 0 : 1;

            float opaity = 20.0;
            float k = opaity * (dens / float(sampleCount)) * transmittance;
            float4 color1 = (1.0).xxxx * k;

            color += (color1 * transmittanceValue * densValue);
            rayOrigin += rayDir * zStep;
        }

        // Fade value allow you to increase the strength of the effect while the camera gets closer to the custom pass volume
        float f = 1 - abs(_FadeValue * 2 - 1);
        float4 rayWS = mul(UNITY_MATRIX_I_VP, float4(0, 0, 0, -_WorldSpaceCameraPos.z));
        float3 rayZPos = ComputeNormalizedDeviceCoordinatesWithZ(rayWS.xyz, UNITY_MATRIX_VP);
        float rayZBuf = rayZPos.z;

        color = (rayZBuf) < (posInput.deviceDepth) ? originColor : color;
        return float4(color.rgb + f, color.a);
    }

    ENDHLSL

    SubShader
    {
        Pass
        {
            Name "Custom Pass 0"

            ZWrite Off
            ZTest Always
            Blend SrcAlpha OneMinusSrcAlpha
            Cull Off

            HLSLPROGRAM
                #pragma fragment FullScreenPass
            ENDHLSL
        }
    }
    Fallback Off
}
