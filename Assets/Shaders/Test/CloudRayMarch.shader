Shader "FullScreen/CloudRayMarch"
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
    #define USE_LIGHT 0

    static float3x3 matOffset = float3x3(
        float3( 0,    0.8,   0.6),
        float3(-0.8,  0.36, -0.48),
        float3(-0.6, -0.48,  0.64)
    );

    struct CloudData {
        float3 position;
        float radius;
    };


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

        float res = lerp(lerp(lerp(Hash(n +   0.0), Hash(n +   1.0), f.x),
                              lerp(Hash(n +  57.0), Hash(n +  58.0), f.x), f.y),
                         lerp(lerp(Hash(n + 113.0), Hash(n + 114.0), f.x),
                              lerp(Hash(n + 170.0), Hash(n + 171.0), f.x), f.y), f.z);
        return res;
    }

    // Fractal Brownian motion
    float Fbm(float3 p)
    {
        float f;
        f =  0.5000 * Noise(p); p = mul(matOffset, p) * 2.02;
        f += 0.2500 * Noise(p); p = mul(matOffset, p) * 2.03;
        f += 0.1250 * Noise(p);
        return f;
    }

    float CloudDist(in float3 rayOrigin, float3 cloudPostion, float cloudRadius)
    {
        return 0.1 - length(rayOrigin - cloudPostion) * (0.25 * (1 / cloudRadius)) + Fbm(rayOrigin * 0.3);
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

        // Add your custom pass code here

        // Fade value allow you to increase the strength of the effect while the camera gets closer to the custom pass volume
        float f = 1 - abs(_FadeValue * 2 - 1);

        float3 rayOrigin = _WorldSpaceCameraPos;
        float3 pos = posInput.positionWS;
        float3 rayDir = normalize(pos);

        // cloud settings
        int sampleCount = 128;
        int sampleLightCount = 6;
        float eps = 0.001;

        // ray marching step settings
        float zMax = 100.0;
        float zStep = zMax / float(sampleCount);

        float zMaxL = 20.0;
        float zStepL = zMaxL / float(sampleLightCount);

        float transmittance = 1.0;

        float absorption = 50.0 * 2;

        float3 lightDir = float3(1.0, 0, 0);
        float4 lightColor = float4(1.0, 0.7, 0.9, 1.0);

        float4 cloudColor = (1.0).xxxx;
        float4 resultColor = (0.0).xxxx;

        CloudData cloudData;
        cloudData.position = float3(0, 0, 10);
        cloudData.radius = 2.5;

        float4 rayWSLong = mul(UNITY_MATRIX_I_VP, float4(0, 0, 0, -(_WorldSpaceCameraPos.z + cloudData.radius)));
        float3 rayZPosLong = ComputeNormalizedDeviceCoordinatesWithZ(rayWSLong.xyz, UNITY_MATRIX_VP);
        float rayZBufLong = rayZPosLong.z;

        float4 rayWSShort = mul(UNITY_MATRIX_I_VP, float4(0, 0, 0, -(_WorldSpaceCameraPos.z - cloudData.radius)));
        float3 rayZPosShort = ComputeNormalizedDeviceCoordinatesWithZ(rayWSShort.xyz, UNITY_MATRIX_VP);
        float rayZBufShort = rayZPosShort.z;

        for (int i = 0; i < sampleCount; i++)
        {
            float density = CloudDist(rayOrigin, cloudData.position, cloudData.radius);
            if (0.0 < density)
            {
                float temp = density / float(sampleCount);
                transmittance *= 1.0 - (temp * absorption);

                if (transmittance <= 0.01)
                {
                    break;
                }
                
                float opaity = 50.0;
                float k = opaity * temp * transmittance;
                float4 color1 = cloudColor * k;

                if (rayZBufShort < posInput.deviceDepth && posInput.deviceDepth < rayZBufLong)
                {
                    color += color1;
                }
                else if(posInput.deviceDepth < rayZBufLong)
                {
                    color += color1 * 2;
                }
            }
            rayOrigin += rayDir * zStep;
        }
        //return float4(color.rgb + f, color.a);
        return color;
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
