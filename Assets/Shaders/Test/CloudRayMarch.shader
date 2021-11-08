Shader "FullScreen/CloudRayMarch"
{
    HLSLINCLUDE

    #pragma vertex Vert

    #pragma target 4.5
    #pragma only_renderers d3d11 playstation xboxone xboxseries vulkan metal switch

    #include "Packages/com.unity.render-pipelines.high-definition/Runtime/RenderPipeline/RenderPass/CustomPass/CustomPassCommon.hlsl"
    
    TEXTURE2D_X(_OutlineBuffer);

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

    struct CloudData {
        float3 position;
        float radius;
        float4 color;
        float transmittance;
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

    float CloudDist(in float3 rayOrigin, in CloudData cloudData)
    {
        return 0.1 - length(rayOrigin - cloudData.position) * (0.25 * (1 / cloudData.radius)) + Fbm(rayOrigin * 0.3);
    }

    float4 GetCloudColor(in CloudData cloudData, in float densSapmle, in float transmittance, in float posDepth)
    {
        float4 densityColor = (0.0).xxxx;
        float4 rayWSLong = mul(UNITY_MATRIX_I_VP, float4(0, 0, 0, -(_WorldSpaceCameraPos.z + cloudData.radius) + cloudData.position.z));
        float3 rayZPosLong = ComputeNormalizedDeviceCoordinatesWithZ(rayWSLong.xyz, UNITY_MATRIX_VP);
        float rayZBufLong = rayZPosLong.z;

        float4 rayWSShort = mul(UNITY_MATRIX_I_VP, float4(0, 0, 0, -(_WorldSpaceCameraPos.z - cloudData.radius) + cloudData.position.z));
        float3 rayZPosShort = ComputeNormalizedDeviceCoordinatesWithZ(rayWSShort.xyz, UNITY_MATRIX_VP);
        float rayZBufShort = rayZPosShort.z;

        float opaity = 50.0;
        float k = opaity * densSapmle * transmittance;
        float4 color1 = cloudData.color * k;

        if (rayZBufShort < posDepth && posDepth < rayZBufLong)
        {
            densityColor += color1;
        }
        else if (posDepth < rayZBufLong)
        {
            densityColor += color1 * 2;
        }
        else
        {
            densityColor += color1;
        }
        return densityColor;
    }

    float UpdateTransmittance(in float oldTransmittance, in float densSapmle, in float absorption)
    {
        float transmittance = oldTransmittance * (1.0 - (densSapmle * absorption));
        return transmittance;
    }

    float4 SetCloud(in float3 rayOrigin, in CloudData cloudData, in int sampleCount, in float absorption, in float posDepth, out float retTransmittance)
    {
        float4 color = (0.0).xxxx;
        float density = CloudDist(rayOrigin, cloudData);
        retTransmittance = cloudData.transmittance;


        if (0.0 < density)
        {
            float densSapmle = density / float(sampleCount);
            float transmittance = UpdateTransmittance(cloudData.transmittance, densSapmle, absorption);

            if (transmittance > 0.01)
            {
                color = GetCloudColor(cloudData, densSapmle, transmittance, posDepth);

                retTransmittance = transmittance;
            }
        }
        return color;
    }

    float4 SetSceneCloudAll(in float3 resRayOrigin, in  float3 posWS, in float3 rayDir, in float posDepth)
    {
        float4 color = (0.0).xxxx;
        // cloud settings
        int sampleCount = 128;

        // ray marching step settings
        float zMax = 100.0;
        float zStep = zMax / float(sampleCount);
        float absorption = 50.0 * 2;


        CloudData cloudData;
        cloudData.position = float3(0, 0, 5);
        cloudData.radius = 5;
        cloudData.color = float4(1, 1, 1, 1);
        cloudData.transmittance = 1.0;

        CloudData cloudDataNew;
        cloudDataNew.position = float3(-10, 0, 5);
        cloudDataNew.radius = 2.5;
        cloudDataNew.color = float4(1, 1, 1, 1);
        cloudDataNew.transmittance = 1.0;

        float3 rayOrigin = resRayOrigin;

        for (int i = 0; i < sampleCount; i++)
        {
            float oldTransmittance = cloudData.transmittance;
            

            if (cloudDataNew.transmittance >= 0.01)
            {
                color += SetCloud(rayOrigin, cloudData, sampleCount, absorption, posDepth, cloudData.transmittance);
            }

            float oldTransmittanceNew = cloudDataNew.transmittance;
            if (cloudDataNew.transmittance >= 0.01)
            {
                color += SetCloud(rayOrigin, cloudDataNew, sampleCount, absorption, posDepth, cloudDataNew.transmittance);
            }

            //color += SetCloud(rayOrigin, cloudData, oldTransmittance, sampleCount, absorption, posDepth, transmittance, endFlag);
            

            rayOrigin += rayDir * zStep;
        }

        //rayOrigin = resRayOrigin;
        //transmittance = 1.0;
        //endFlag = false;
        //
        //for (int j = 0; j < sampleCount; j++)
        //{
        //    float oldTransmittance = transmittance;
        //
        //
        //    if (endFlag == true)
        //    {
        //        break;
        //    }
        //
        //    color += SetCloud(rayOrigin, cloudData, oldTransmittance, sampleCount, absorption, posDepth, transmittance, endFlag);
        //    //color += SetCloud(rayOrigin, cloudDataNew, oldTransmittance, sampleCount, absorption, posDepth, transmittance, endFlag);
        //
        //    rayOrigin += rayDir * zStep;
        //}

        return color;
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

        color = SetSceneCloudAll(rayOrigin, pos, rayDir, posInput.deviceDepth);
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
