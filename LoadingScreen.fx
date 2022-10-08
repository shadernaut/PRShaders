
#include "shaders/RealityGraphics.fx"

/*
	[Attributes from app]
*/

uniform float4x4 _WorldViewProj : TRANSFORM;

/*
	[Textures and samplers]
*/

uniform texture TexMap : TEXTURE;

sampler Sampler_TexMap = sampler_state
{
    Texture = (TexMap);
    AddressU = WRAP;
    AddressV = WRAP;
    MinFilter = LINEAR;
    MagFilter = LINEAR;
    MipFilter = LINEAR;
};

struct APP2VS
{
	float3 Pos : POSITION;
	float2 Tex : TEXCOORD0;
	float4 Color : COLOR0;
};

struct VS2PS
{
	float4 HPos : POSITION;
	float2 Tex : TEXCOORD0;
	float4 Color : COLOR0;
};

VS2PS Screen_VS(APP2VS Input)
{
	VS2PS Output = (VS2PS)0;
	Output.HPos = float4(Input.Pos.xy, 0.0, 1.0);
	Output.Tex = Input.Tex;
	Output.Color = saturate(Input.Color);
	return Output;
}

float4 Screen_PS(VS2PS Input) : COLOR
{
	float4 InputTexture0 = tex2D(Sampler_TexMap, Input.Tex);
	float4 OutputColor;
	OutputColor.rgb = InputTexture0.rgb * Input.Color.rgb;
	OutputColor.a = Input.Color.a;
	return OutputColor;
}

technique Screen
{
	pass P0
	{
		VertexShader = compile vs_3_0 Screen_VS();
		PixelShader = compile ps_3_0 Screen_PS();

		AlphaBlendEnable = FALSE;
		StencilEnable = FALSE;
		AlphaTestEnable = FALSE;
		CullMode = NONE;
	}
}