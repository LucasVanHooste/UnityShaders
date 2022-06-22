Shader "Unlit/ComicBook"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        [MainColor] _Color ("Color", Color) = (1, 1, 1, 1)
        _OutlineWidth ("Outline Width", Range(0, .01)) = .005
        [Header(Dots)][Space]
        _DotSize ("Dot Size", Range(0, 1)) = .36
        _DotScale ("Dot Scale", Range(0, .05)) = .025
        _ScaleDistExp ("Dot Distance Scaling Exponent", Range(0, 1)) = .75
        [Header(Shading)][Space]
        _ShadowAdjustment ("Shadow Adjustment", Range(-1, 1)) = 0
        _HighlightAdjustment ("Highlight Adjustment", Range(-1, 1)) = -1
        [Header(Color Remapping)][Space]
        _WhiteThreshold ("White Threshold", Range(0, 1)) = .2
        _BlackThreshold ("Black Threshold", Range(0, 1)) = .2
        _Color1 ("Color 1", Color) = (0.783,0,0,1)
        _Color2 ("Color 2", Color) = (0.996,0.90,0,1)
        _Color3 ("Color 3", Color) = (0,0,0.463,1)
    }
    SubShader
    {
        Pass
        {
            Name "Shadow Caster"
            Tags {"RenderType"="Opaque" "LightMode"="ShadowCaster"}
            ZWrite On

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_shadowcaster
            #include "UnityCg.cginc"

            struct appdata{
                float4 vertex : POSITION0;
                float3 normal : NORMAL;
            };

            struct v2f{
                V2F_SHADOW_CASTER;
            };

            v2f vert (appdata v)
            {
                v2f o;
                TRANSFER_SHADOW_CASTER_NORMALOFFSET(o)
                return o;
            }
            fixed4 frag (v2f i) : SV_Target
            {
                SHADOW_CASTER_FRAGMENT (i)
            }
            ENDCG
        }

        Pass
        {
            Tags { "RenderType"="Opaque" "LightMode"="ForwardBase" }

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog
            #pragma multi_compile_fwdbase nolightmap nodirlightmap nodynlightmap novertexlight

            #include "UnityCG.cginc"
            #include "AutoLight.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                UNITY_FOG_COORDS(1)
                float4 vertex : SV_POSITION;
                float3 vertex_world : TEXCOORD1;
                float4 screenPosition : TEXCOORD2;
                float3 normal_world : NORMAL;
            };

            sampler2D _MainTex;
            float4 _Color;
            float4 _MainTex_ST;
            //dots
            float _DotSize;
            float _DotScale;
            float _ScaleDistExp;
            //shading
            float4 _LightColor0;
            float _ShadowAdjustment;
            float _HighlightAdjustment;
            //color remapping
            float _WhiteThreshold;
            float _BlackThreshold;
            float3 _Color1;
            float3 _Color2;
            float3 _Color3;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.vertex_world = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.screenPosition = ComputeScreenPos(o.vertex);
                o.normal_world = UnityObjectToWorldNormal(v.normal);
                UNITY_TRANSFER_FOG(o,o.vertex);
                return o;
            }

            void Unity_Rotate_Degrees_float(float2 UV, float2 Center, float Rotation, out float2 Out)
            {
                Rotation = Rotation * (UNITY_PI/180.0f);
                UV -= Center;
                float s = sin(Rotation);
                float c = cos(Rotation);
                float2x2 rMatrix = float2x2(c, -s, s, c);
                rMatrix *= 0.5;
                rMatrix += 0.5;
                rMatrix = rMatrix * 2 - 1;
                UV.xy = mul(UV.yx, rMatrix);
                UV += Center;
                Out = UV;
            }

            float Shading(float lightIntensity, float3 lightDirection, float3 normal){
                return lightIntensity * dot(lightDirection, normal);
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float4 col;
                fixed4 sampledCol = tex2D(_MainTex, i.uv);

                //black/white remapping
                float maxDiff = max(abs(sampledCol.x - sampledCol.y), max(abs(sampledCol.x - sampledCol.z), abs(sampledCol.y - sampledCol.z)));
                int white = (length(sampledCol.xyz) > 1.73 - _WhiteThreshold) | maxDiff < _WhiteThreshold; //1.73 is mag of float3(1,1,1)
                int black = length(sampledCol.xyz) < _BlackThreshold;
                if(white | black){
                    col = float4(1,1,1,1) * (white - black) + float4(0,0,0,1) * black;
                }
                else
                {
                    //color remapping
                    sampledCol *= _Color;

                    float dot1 = dot(sampledCol.xyz, _Color1) / length(_Color1);
                    float dot2 = dot(sampledCol.xyz, _Color2) / length(_Color2);
                    float dot3 = dot(sampledCol.xyz, _Color3) / length(_Color3);
                    float greatest = max(dot1, max(dot2, dot3));
                    sampledCol.xyz = ((greatest == dot1) * _Color1) + ((greatest == dot2) * _Color2) + ((greatest == dot3) * _Color3);
                    
                    if(sampledCol.w > .75) //use full color if alpha is higher than value
                    {
                        col = sampledCol;
                    }
                    else //dot pattern
                    {
                        float2 screenPos = i.screenPosition.xy / i.screenPosition.w;
                        screenPos.x *= _ScreenParams.x / _ScreenParams.y; //aspect ratio correction
                        Unity_Rotate_Degrees_float(screenPos, float2(0, 0), 45, screenPos);
                        //factor object camera distance into dot scale
                        float camDist = length(UnityWorldSpaceViewDir(mul(unity_ObjectToWorld, float4(0, 0, 0, 1))));
                        float scale =  _DotScale / pow(camDist, _ScaleDistExp); 
                        float2 scaledPos = abs(screenPos % scale) - scale / 2;

                        int inRadius = length(scaledPos) < _DotSize * scale;
                        col = (inRadius ^ sampledCol.w > .25) * sampledCol + (inRadius ^ sampledCol.w < .25) * float4(1,1,1,1);
                    }

                }
                //shading
                float3 lightDir = normalize(_WorldSpaceLightPos0.xyz);
                float diffuseShading = Shading(length(_LightColor0), lightDir, i.normal_world);
                col.rgb *= diffuseShading + _ShadowAdjustment > 0;
                col.rgb += diffuseShading + _HighlightAdjustment > 1;

                // apply fog
                UNITY_APPLY_FOG(i.fogCoord, col);
                return col;
            }
            ENDCG
        }

        Pass
        {
            Name "Outline"
            Tags { "RenderType"="Opaque" "LightMode"="ForwardBase" }
            Cull Front

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog
            #pragma multi_compile_fwdbase nolightmap nodirlightmap nodynlightmap novertexlight

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
            };

            struct v2f
            {
                UNITY_FOG_COORDS(1)
                float4 vertex : SV_POSITION;
            };

            float _OutlineWidth;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                float3 viewNormal = normalize(mul ((float3x3)UNITY_MATRIX_IT_MV, v.normal)); //normalizing is done so object scale doesn't affect outline
                float2 normal_clip = TransformViewToProjection(viewNormal.xy);
                o.vertex.xy += normal_clip.xy * _OutlineWidth;
                UNITY_TRANSFER_FOG(o,o.vertex);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                float4 col = float4(0,0,0,1);
                UNITY_APPLY_FOG(i.fogCoord, col);
                return col;
            }
            ENDCG
        }
    }
}
