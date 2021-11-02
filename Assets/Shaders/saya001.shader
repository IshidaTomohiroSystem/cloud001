Shader "FullScreen/saya001"
{
    HLSLINCLUDE

    #pragma vertex Vert

    #pragma target 4.5
    #pragma only_renderers d3d11 ps4 xboxone vulkan metal switch

    #include "Packages/com.unity.render-pipelines.high-definition/Runtime/RenderPipeline/RenderPass/CustomPass/CustomPassCommon.hlsl"
    static float EPS = 1e-4;
    static float OFFSET = EPS * 10.0;
    //static float PI = 3.14159;
    static float INF = 1e+10;

    static float3 lightDir = float3(-0.48666426339228763, 0.8111071056538127, -0.3244428422615251);
    static float3 backgroundColor = (0.0).xxx;
    static float3 gateColor = float3(1.0, 0.1, 0.1);

    static float totalTime = 75.0;
    static int BASIC_MATERIAL = 0;
    static int MIRROR_MATERIAL = 1;

    float3 cPos, cDir;
    float normalizedGlobalTime = 0.0;
    struct Intersect {
        bool isHit;

        float3 position;
        float distance;
        float3 normal;

        int material;
        float3 color;
    };

    float mod(float x, float y)
    {
        return x - y * floor(x / y);
    }

    float2 mod(float2 x, float y)
    {
        return x - y * floor(x / y);
    }

    float3 mod(float3 x, float y)
    {
        return x - y * floor(x / y);
    }

    // distance functions
    float3 opRep(float3 p, float interval) {
        return mod(p, interval) - 0.5 * interval;
    }

    float2 opRep(float2 p, float interval) {
        return mod(p, interval) - 0.5 * interval;
    }

    float opRep(float x, float interval) {
        return mod(x, interval) - 0.5 * interval;
    }

    float sphereDist(float3 p, float3 c, float r) {
        return length(p - c) - r;
    }

    float sdCappedCylinder(float3 p, float2 h) {
        float2 d = abs(float2(length(p.xz), p.y)) - h;
        return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
    }

    float udBox(float3 p, float3 b)
    {
        return length(max(abs(p) - b, 0.0));
    }

    float udFloor(float3 p) {
        float t1 = 1.0;
        float t2 = 3.0;
        float d = -0.5;
        for (float i = 0.0; i < 3.0; i++) {
            float f = pow(2.0, i);
            d += 0.1 / f * (sin(f * t1 * p.x + t2 * _Time.y) + sin(f * t1 * p.z + t2 * _Time.y));
        }
        return dot(p, float3(0.0, 1.0, 0.0)) - d;
    }

    float dGate(float3 p) {
        p.y -= 1.3 * 0.5;

        float r = 0.05;
        float left = sdCappedCylinder(p - float3(-1.0, 0.0, 0.0), float2(r, 1.3));
        float right = sdCappedCylinder(p - float3(1.0, 0.0, 0.0), float2(r, 1.3));

        float ty = 0.02 * p.x * p.x;
        float tx = 0.5 * (p.y - 1.3);
        float katsura = udBox(p - float3(0.0, 1.3 + ty, 0.0), float3(1.7 + tx, r * 2.0 + ty, r));

        float kan = udBox(p - float3(0.0, 0.7, 0.0), float3(1.3, r, r));
        float gakuduka = udBox(p - float3(0.0, 1.0, 0.0), float3(r, 0.3, r));

        return min(min(left, right), min(gakuduka, min(katsura, kan)));
    }

    float dRepGate(float3 p) {
        if (normalizedGlobalTime <= 0.5) {
            p.z = opRep(p.z, 1.0 + 20.0 * cos(PI * normalizedGlobalTime));
        }
        else {
            p.xz = opRep(p.xz, 10.0);
        }
        return dGate(p);
    }

    float sceneDistance(float3 p) {
        return udFloor(p);
    }

    // color functions
    float3 hsv2rgb(float3 c) {

        float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
        float3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
        return c.z * lerp(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);

    }

    Intersect minIntersect(Intersect a, Intersect b) {
        if (a.distance < b.distance) {
            return a;
        }
        else {
            return b;
        }
    }

    Intersect sceneIntersect(float3 p) {

        Intersect a;
        a.distance = udFloor(p);
        a.material = MIRROR_MATERIAL;
        // return minIntersect( a, b );
        return a;
    }

    float3 getNormal(float3 p) {
        float2 e = float2(1.0, -1.0) * 0.001;
        return normalize(
            e.xyy * sceneDistance(p + e.xyy) + e.yyx * sceneDistance(p + e.yyx) +
            e.yxy * sceneDistance(p + e.yxy) + e.xxx * sceneDistance(p + e.xxx));
    }

    float getShadow(float3 ro, float3 rd) {

        float h = 0.0;
        float c = 0.0;
        float r = 1.0;
        float shadowCoef = 0.5;

        for (float t = 0.0; t < 50.0; t++) {

            h = sceneDistance(ro + rd * c);

            if (h < EPS) return shadowCoef;

            r = min(r, h * 16.0 / c);
            c += h;

        }

        return 1.0 - shadowCoef + r * shadowCoef;

    }

    Intersect getRayColor(float3 origin, float3 ray) {

        // marching loop
        float dist, minDist, trueDepth;
        float depth = 0.0;
        float3 p = origin;
        int count = 0;
        Intersect nearest;
        nearest.color = (0.0).xxx;
        nearest.distance = 0.0;


        // first pass (water)
        for (int i = 0; i < 120; i++) {

            dist = sceneDistance(p);
            depth += dist;
            p = origin + depth * ray;

            count = i;
            if (abs(dist) < EPS) break;

        }

        if (abs(dist) < EPS) {

            nearest = sceneIntersect(p);
            nearest.position = p;
            nearest.normal = getNormal(p);
            nearest.distance = depth;
            float diffuse = clamp(dot(lightDir, nearest.normal), 0.1, 1.0);
            float specular = pow(clamp(dot(reflect(lightDir, nearest.normal), ray), 0.0, 1.0), 6.0);
            //float shadow = getShadow( p + nearest.normal * OFFSET, lightDir );

            if (nearest.material == BASIC_MATERIAL) {
            }
            else if (nearest.material == MIRROR_MATERIAL) {
                nearest.color = float3(0.5, 0.7, 0.8) * diffuse + (1.0).xxx * specular;
            }

            nearest.isHit = true;

        }
        else {

            nearest.color = backgroundColor;
            nearest.isHit = false;

        }
        nearest.color = clamp(nearest.color - 0.1 * nearest.distance, 0.0, 1.0);

        // second pass (gates)
        p = origin;
        depth = 0.0;
        minDist = INF;
        for (int j = 0; j < 20; j++) {
            dist = dRepGate(p);
            minDist = min(dist, minDist);
            /*if ( dist < minDist ) {
                minDist = dist;
                trueDepth = depth;
            }*/
            depth += dist;
            p = origin + depth * ray;
            if (j == 9 && normalizedGlobalTime <= 0.5) {
                break;
            }
        }

        if (abs(dist) < EPS) {
            nearest.color += gateColor;
        }
        else {
            nearest.color += gateColor * clamp(0.05 / minDist, 0.0, 1.0);
        }

        return nearest;

    }


    float4 FullScreenPass(Varyings varyings) : SV_Target
    {
        float depth = LoadCameraDepth(varyings.positionCS.xy);
        PositionInputs posInput = GetPositionInput(varyings.positionCS.xy, _ScreenSize.zw, depth, UNITY_MATRIX_I_VP, UNITY_MATRIX_V);
        float4 color = float4(0.0, 0.0, 0.0, 0.0);
        if (_CustomPassInjectionPoint != CUSTOMPASSINJECTIONPOINT_BEFORE_RENDERING)
            color = float4(CustomPassSampleCameraColor(posInput.positionNDC.xy, 0), 1);
        normalizedGlobalTime = mod(_Time.y / totalTime, 1.0);

        //		float2 uv = i.uv;
        //		float2 uv = posInput.positionNDC.xy;
        //		float2 p = 2.0 * i.uv - 1.0;
        float2 p = (2. * varyings.positionCS.xy - _ScreenSize.xy) / min(_ScreenSize.x, _ScreenSize.y);
        //		float2 p = 2.*uv - 1.;
        //float2 p = (fragCoord.xy * 2.0 - iResolution.xy) / min(iResolution.x, iResolution.y);
       
        // camera and ray
        if (normalizedGlobalTime < 0.7) {
            cPos = float3(0.0, 0.6 + 0.4 * cos(_Time.y), 3.0 * _Time.y);
            cDir = normalize(float3(0.0, -0.1, 1.0));
        }
        else {
            cPos = float3(0.0, 0.6 + 0.4 * cos(_Time.y) + 50.0 * (normalizedGlobalTime - 0.7), 3.0 * _Time.y);
            cDir = normalize(float3(0.0, -0.1 - (normalizedGlobalTime - 0.7), 1.0));
        }
        float3 cSide = normalize(cross(cDir, float3(0.0, 1.0, 0.0)));
        float3 cUp = normalize(cross(cSide, cDir));
        float targetDepth = 1.3;
        float3 ray = normalize(cSide * p.x + cUp * p.y + cDir * targetDepth);
       
        // Illumination col
        // illuminationcol = hsv2rgb( float3( _Time.y * 0.02 + 0.6, 1.0, 1.0 ) );
       
        float3 col = (0.0).xxx;
        float alpha = 1.0;
        Intersect nearest;
       
        for (int i = 0; i < 3; i++) {
       
            nearest = getRayColor(cPos, ray);
       
            col += (alpha * nearest.color);
            alpha *= 0.5;
            ray = normalize(reflect(ray, nearest.normal));
            cPos = nearest.position + nearest.normal * OFFSET;
       
            if (!nearest.isHit || nearest.material != MIRROR_MATERIAL)
                break;
        }
       
        color.rgb = col;
       
        return color;
    }

    ENDHLSL

    SubShader
    {
        Pass
        {
            Name "Custom Pass4"

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
