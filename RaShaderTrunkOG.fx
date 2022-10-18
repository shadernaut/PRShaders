
/*
	Description: Renders lighting for tree-trunk overgrowth
*/

#include "shaders/RealityGraphics.fx"

#include "shaders/RaCommon.fx"

Light Lights[1];
float4 OverGrowthAmbient;
float4 ObjectSpaceCamPos;
float4 PosUnpack;

texture DiffuseMap;
sampler DiffuseMapSampler = sampler_state
{
	Texture = (DiffuseMap);
	MipFilter = LINEAR;
	MinFilter = LINEAR;
	MagFilter = LINEAR;
	AddressU = WRAP;
	AddressV = WRAP;
};

string GlobalParameters[] =
{
	"GlobalTime",
	"FogRange",
	"FogColor",
};

string TemplateParameters[] =
{
	"PosUnpack",
	"DiffuseMap",
};

string InstanceParameters[] =
{
	"WorldViewProjection",
	"Lights",
	"ObjectSpaceCamPos",
	"OverGrowthAmbient",
	"Transparency",
};

// INPUTS TO THE VERTEX SHADER FROM THE APP
string reqVertexElement[] =
{
	"Position",
	"Normal",
	"TBase2D"
};

struct APP2VS
{
	float4 Pos : POSITION0;
	float3 Normal : NORMAL;
	float2 Tex0 : TEXCOORD0;
};

struct VS2PS
{
	float4 HPos : POSITION;
	float2 Tex0 : TEXCOORD0;
	float4 P_Normals_ScaleLN : TEXCOORD1; // .xyz = Normals; .w = ScaleLN;
	float3 VertexPos : TEXCOORD2;
};

VS2PS TrunkOG_VS(APP2VS Input)
{
	VS2PS Output = (VS2PS)0;

	Output.HPos = mul(float4(Input.Pos.xyz, 1.0), WorldViewProjection);
	Output.Tex0.xy = Input.Tex0 / 32767.0;
	Output.P_Normals_ScaleLN.xyz = normalize(Input.Normal * 2.0 - 1.0);
	Output.P_Normals_ScaleLN.w = Input.Pos.w / 32767.0;
	Output.VertexPos = Input.Pos.xyz * PosUnpack.xyz;

	return Output;
}

// There will be small differences between this lighting and the one produced by the static mesh shader,
// not enough to worry about, ambient is added here and lerped in the static mesh, etc
// NOTE: could be an issue at some point.
float4 TrunkOG_PS(VS2PS Input) : COLOR
{
	float4 DiffuseMap = tex2D(DiffuseMapSampler, Input.Tex0.xy);
	float3 Normals = normalize(Input.P_Normals_ScaleLN.xyz);
	float3 Diffuse = GetDiffuse(Normals.xyz, -Lights[0].dir) * Lights[0].color;

	float ScaleLN = Input.P_Normals_ScaleLN.w;
	float3 Color = (OverGrowthAmbient.rgb + Diffuse) * ScaleLN;

	float4 FinalColor = float4((DiffuseMap.rgb * Color.rgb) * 2.0, Transparency.a);
	FinalColor.rgb = ApplyFog(FinalColor.rgb, GetFogValue(Input.VertexPos.xyz, ObjectSpaceCamPos.xyz));
	return FinalColor;
};

technique defaultTechnique
{
	pass P0
	{
		VertexShader = compile vs_3_0 TrunkOG_VS();
		PixelShader = compile ps_3_0 TrunkOG_PS();

		#if defined(ENABLE_WIREFRAME)
			FillMode = WireFrame;
		#endif
	}
}
