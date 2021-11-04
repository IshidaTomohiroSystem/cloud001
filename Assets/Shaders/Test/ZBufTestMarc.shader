Shader "FullScreen/ZBufTestMarc"
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

    float DistSphere(float3 position, float radius)
    {
        return length(position) - radius;
    }

    float ShortestDistance(float3 position)
    {
        return DistSphere(position, 0.5);
    }

    float3 GetNormal(float3 position)
    {
        float2 e = float2(1.0, -1.0) * 0.001;

        return normalize(
            e.xyy * ShortestDistance(position + e.xyy) + e.yyx * ShortestDistance(position + e.yyx) +
            e.yxy * ShortestDistance(position + e.yxy) + e.xxx * ShortestDistance(position + e.xxx));
    }

    float3 GetColor(float3 rayOrigin, float3 lightDir, float3 lightColor)
    {
        float3 color;
        float3 normal = GetNormal(rayOrigin);
        float diffuse = clamp(dot(lightDir, normal), 0.1, 1.0);
        //float specular = pow(clamp(dot(reflect(lightDir, normal), rayOrigin - minObjData.position), 0.0, 1.0), 6.0);

        color = lightColor * diffuse;// +(1.0).xxx * specular;
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
        float3 rayDir = normalize(posInput.positionWS);
        float3 pos = posInput.positionWS;


        for (int i = 0; i < 30; i++)
        {
            float dist = ShortestDistance(rayOrigin);
            if (dist < 0.001)
            {
                float4 rayWS = mul(UNITY_MATRIX_I_VP, float4(0, 0, 0, -_WorldSpaceCameraPos.z));
                float3 rayZPos = ComputeNormalizedDeviceCoordinatesWithZ(rayWS.xyz, UNITY_MATRIX_VP);
                float rayZBuf = rayZPos.z;

                if ((rayZBuf) > (posInput.deviceDepth))
                {
                    float3 col = GetColor(rayOrigin, float3(1, 1, 0), float3(1, 1, 1));
                    return float4(col, 1.0);
                }

            }
            rayOrigin += rayDir.xyz * dist;
        }

        //return float4(-1 + 1000 / posInput.linearDepth, 0, 0, 1);
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
