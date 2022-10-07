
#include "shaders/RaCommon.fx"

#define LIGHT_MUL float3(0.8, 0.8, 0.4)
#define LIGHT_ADD float3(0.4, 0.4, 0.4)

float3 TerrainSunColor;
float2 RoadFadeOut;
float4 WorldSpaceCamPos;
// float RoadDepthBias;
// float RoadSlopeScaleDepthBias;

float4 PosUnpack;
float TexUnpack;

texture	LightMap;
sampler LightMapSampler = sampler_state
{
	Texture = (LightMap);
	MipFilter = LINEAR;
	MinFilter = LINEAR;
	MagFilter = LINEAR;
	AddressU = WRAP;
	AddressV = WRAP;
};

#if defined(USE_DETAIL)
	texture	DetailMap;
	sampler DetailMapSampler = sampler_state
	{
		Texture = (DetailMap);
		MipFilter = LINEAR;
		MinFilter = FILTER_STM_DIFF_MIN;
		MagFilter = FILTER_STM_DIFF_MAG;
		MaxAnisotropy = 16;
		AddressU = WRAP;
		AddressV = WRAP;
	};
#endif

texture	DiffuseMap;
sampler DiffuseMapSampler = sampler_state
{
	Texture = (DiffuseMap);
	MipFilter = LINEAR;
	MinFilter = FILTER_STM_DIFF_MIN;
	MagFilter = FILTER_STM_DIFF_MAG;
	MaxAnisotropy = 16;
	AddressU = WRAP;
	AddressV = WRAP;
};

string GlobalParameters[] =
{
	"FogRange",
	"FogColor",
	"ViewProjection",
	"TerrainSunColor",
	"RoadFadeOut",
	"WorldSpaceCamPos",
	// "RoadDepthBias",
	// "RoadSlopeScaleDepthBias"
};

string TemplateParameters[] =
{
	"DiffuseMap",
	#if defined(USE_DETAIL)
		"DetailMap",
	#endif
};

string InstanceParameters[] =
{
	"World",
	"Transparency",
	"LightMap",
	"PosUnpack",
	"TexUnpack",
};

// INPUTS TO THE VERTEX SHADER FROM THE APP
string reqVertexElement[] =
{
	"PositionPacked",
	"TBasePacked2D",
	#if defined(USE_DETAIL)
		"TDetailPacked2D",
	#endif
};

struct APP2VS
{
	float4 Pos : POSITION0;
	float2 Tex0 : TEXCOORD0;
	#if defined(USE_DETAIL)
		float2 Tex1 : TEXCOORD1;
	#endif
};

struct VS2PS
{
	float4 Pos : POSITION0;
	float4 P_Tex0_Tex1 : TEXCOORD0; // .xy = Tex0; .zw = Tex1;
	float4 P_VertexPos_ZFade : TEXCOORD1; // .xyz = VertexPos; .w = ZFade;
	float4 LightTex : TEXCOORD2;
};

VS2PS Editor_Road_VS(APP2VS Input)
{
	VS2PS Output = (VS2PS)0;

	float4 WorldPos = mul(Input.Pos * PosUnpack, World);
	WorldPos.y += 0.01;

	Output.Pos = mul(WorldPos, ViewProjection);
	Output.P_Tex0_Tex1.xy = Input.Tex0 * TexUnpack;
	#if defined(USE_DETAIL)
		Output.P_Tex0_Tex1.zw = Input.Tex1 * TexUnpack;
	#endif

	Output.LightTex.xy = Output.Pos.xy / Output.Pos.w;
	Output.LightTex.xy = Output.LightTex.xy * float2(0.5, -0.5) + float2(0.5, 0.5);
	Output.LightTex.xy = Output.LightTex.xy * Output.Pos.w;
	Output.LightTex.zw = Output.Pos.zw;

	Output.P_VertexPos_ZFade.xyz = WorldPos.xyz;
	Output.P_VertexPos_ZFade.w = 1.0 - saturate((distance(WorldPos.xyz, WorldSpaceCamPos.xyz) * RoadFadeOut.x) - RoadFadeOut.y);

	return Output;
}

float4 Editor_Road_PS(VS2PS Input) : COLOR
{
	float4 Diffuse = tex2D(DiffuseMapSampler, Input.P_Tex0_Tex1.xy);

	#if defined(USE_DETAIL)
		float4 Detail = tex2D(DetailMapSampler, Input.P_Tex0_Tex1.zw);
		float4 Color = Diffuse * Detail;
	#else
		float4 Color = Diffuse;
	#endif

	Color.rgb = ApplyFog(Color.rgb, GetFogValue(Input.P_VertexPos_ZFade.xyz, WorldSpaceCamPos.xyz));
	Color.a *= Input.P_VertexPos_ZFade.w;
	return Color;
};

technique defaultTechnique
{
	pass P0
	{
		#if defined(ENABLE_WIREFRAME)
			FillMode = WireFrame;
		#endif

		CullMode = CCW;
		AlphaBlendEnable = TRUE;
		AlphaTestEnable = FALSE;

		SrcBlend = SRCALPHA;
		DestBlend = INVSRCALPHA;

		ZEnable	= TRUE;
		ZWriteEnable = FALSE;

		// DepthBias = < RoadDepthBias >;
		// SlopeScaleDepthBias = < RoadSlopeScaleDepthBias >;

		VertexShader = compile vs_3_0 Editor_Road_VS();
		PixelShader = compile ps_3_0 Editor_Road_PS();
	}
}
