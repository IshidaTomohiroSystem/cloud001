Shader "FullScreen/SphereRayMarch2"
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
    struct ObjectData {
        float3 position;
        float3 color;
    };

    struct MinDistPosition {
        float dist;
        ObjectData data;
    };

    static ObjectData sphereOne;
    static ObjectData sphereTwo;

    float Sphere(float3 position, float radius)
    {
        return length(position) - radius;
    }

    MinDistPosition ShortestDistance(float3 position)
    {
        float dist1 = Sphere(position, 1);
        float dist2 = Sphere(position - sphereTwo.position, 1);

        float minDist = min(dist1, dist2);

        MinDistPosition minDistPosition;
        minDistPosition.dist = minDist;

        if (min(dist1, dist2) == dist1)
        {
            minDistPosition.data = sphereOne;
        }
        else if(min(dist1, dist2) == dist2)
        {
            minDistPosition.data = sphereTwo;
        }

        return minDistPosition;
    }

    float3 GetNormal(float3 position)
    {
        float2 e = float2(1.0, -1.0) * 0.001;

        return normalize(
            e.xyy * ShortestDistance(position + e.xyy).dist + e.yyx * ShortestDistance(position + e.yyx).dist +
            e.yxy * ShortestDistance(position + e.yxy).dist + e.xxx * ShortestDistance(position + e.xxx).dist);
    }

    float3 GetColor(float3 rayOrigin, float3 lightDir, float3 lightColor, ObjectData minObjData)
    {
        float3 color;
        float3 normal = GetNormal(rayOrigin);
        float diffuse = clamp(dot(lightDir, normal), 0.1, 1.0);
        //float specular = pow(clamp(dot(reflect(lightDir, normal), rayOrigin - minObjData.position), 0.0, 1.0), 6.0);

        color = minObjData.color * lightColor * diffuse;// +(1.0).xxx * specular;
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
        //return float4(color.rgb + f, color.a);

        float3 pos = posInput.positionWS;

        float3 rayOrigin = _WorldSpaceCameraPos;
        float3 rayDir = normalize(float3(pos.xyz));


        int stepNum = 30;
        float3 lightDir = normalize(float3(0.5, 0.8, -0.5));
        float3 lightColor = float3(1, 1, 1);
        float3 col = (0.0).xxx;


        sphereOne.position = float3(0.0, 0.0, 0.0);
        sphereOne.color = float3(1.0, 1.0, 1.0);

        sphereTwo.position = float3(2.0, 2.0, 0.0);
        sphereTwo.color = float3(1.0, 1.0, 0.0);



        for (int i = 0; i < stepNum; i++)
        {
            MinDistPosition minDistPosition = ShortestDistance(rayOrigin);
            float marchingDist = minDistPosition.dist;
            // 0.0011以下になったら、ピクセルを白で塗って処理終了
            if (marchingDist < 0.001)
            {
                col = GetColor(rayOrigin, lightDir, lightColor, minDistPosition.data);
                return float4(col, 1.0);
            }
            rayOrigin += rayDir.xyz * marchingDist;
        }

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
