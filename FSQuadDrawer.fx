
/*
	Description:

	Shader that handles most of the screen-space post processing and texture conversions in the game.
	The shader includes the following
	1. Blurs (glow, blur, downsample, upsample, etc.)
	2. Texture conversions to 8-bit

	Changes:
	1. Removed Shader Model 1.4 shaders (these were done because arbitrary texture coordinate swizzling wasn't a thing in Shader Model 1.x)
	2. Many shaders now use bilinear filtering instead of point filtering (linear filtering was more expensive for certain cards back then)
	3. Updated shaders to Shader Model 3.0 for access to ddx, ddy, and non-gradient texture instructions
	4. Redid coding conventions
*/

#include "shaders/RealityGraphics.fx"

/*
	[Attributes from app]
*/

uniform dword _dwordStencilRef : STENCILREF = 0;
uniform dword _dwordStencilPass : STENCILPASS = 1; // KEEP

uniform float4x4 _ConvertPosTo8BitMat : CONVERTPOSTO8BITMAT;
uniform float4x4 _CustomMtx : CUSTOMMTX;

// Convolution attributes passed from the app
uniform float4 _ScaleDown2x2SampleOffsets[4] : SCALEDOWN2X2SAMPLEOFFSETS;
uniform float4 _ScaleDown4x4SampleOffsets[16] : SCALEDOWN4X4SAMPLEOFFSETS;
uniform float4 _ScaleDown4x4LinearSampleOffsets[4] : SCALEDOWN4X4LINEARSAMPLEOFFSETS;
uniform float4 _GaussianBlur5x5CheapSampleOffsets[13] : GAUSSIANBLUR5X5CHEAPSAMPLEOFFSETS;
uniform float _GaussianBlur5x5CheapSampleWeights[13] : GAUSSIANBLUR5X5CHEAPSAMPLEWEIGHTS;
uniform float4 _GaussianBlur15x15HorizontalSampleOffsets[15] : GAUSSIANBLUR15X15HORIZONTALSAMPLEOFFSETS;
uniform float _GaussianBlur15x15HorizontalSampleWeights[15] : GAUSSIANBLUR15X15HORIZONTALSAMPLEWEIGHTS;
uniform float4 _GaussianBlur15x15VerticalSampleOffsets[15] : GAUSSIANBLUR15X15VERTICALSAMPLEOFFSETS;
uniform float _GaussianBlur15x15VerticalSampleWeights[15] : GAUSSIANBLUR15X15VERTICALSAMPLEWEIGHTS;
uniform float4 _GrowablePoisson13SampleOffsets[12] : GROWABLEPOISSON13SAMPLEOFFSETS;

// Glow attributes passed from the app
uniform float _GlowHorizOffsets[5] : GLOWHORIZOFFSETS;
uniform float _GlowHorizWeights[5] : GLOWHORIZWEIGHTS;
uniform float _GlowVertOffsets[5] : GLOWVERTOFFSETS;
uniform float _GlowVertWeights[5] : GLOWVERTWEIGHTS;

// Glow attributes passed from the app
uniform float _BloomHorizOffsets[5] : BLOOMHORIZOFFSETS;
uniform float _BloomVertOffsets[5] : BLOOMVERTOFFSETS;

// Other attributes passed from the app (render.)
uniform float _HighPassGate : HIGHPASSGATE; // 3d optics blur; xxxx.yyyy; x - aspect ratio(H/V), y - blur amount(0=no blur, 0.9=full blur)
uniform float _BlurStrength : BLURSTRENGTH; // 3d optics blur; xxxx.yyyy; x - inner radius, y - outer radius

uniform float2 _TexelSize : TEXELSIZE;

/*
	[Textures and samplers]
*/

uniform texture Texture_0 : TEXLAYER0;
uniform texture Texture_1 : TEXLAYER1;

// uniform texture Texture_2 : TEXLAYER2;
// uniform texture Texture_3 : TEXLAYER3;

/*
	sampler Sampler2 = sampler_state
	{
		Texture = (Texture_2);
		AddressU = CLAMP;
		AddressV = CLAMP;
		MinFilter = POINT;
		MagFilter = POINT;
	};

	sampler Sampler3 = sampler_state
	{
		Texture = (Texture_3);
		AddressU = CLAMP;
		AddressV = CLAMP;
		MinFilter = POINT;
		MagFilter = POINT;
	};
*/

sampler Sampler_0_Bilinear = sampler_state
{
	Texture = (Texture_0);
	AddressU = CLAMP;
	AddressV = CLAMP;
	MinFilter = LINEAR;
	MagFilter = LINEAR;
};

sampler Sampler_0_Bilinear_Mirror = sampler_state
{
	Texture = (Texture_0);
	AddressU = MIRROR;
	AddressV = MIRROR;
	MinFilter = LINEAR;
	MagFilter = LINEAR;
};

sampler Sampler_0_Anisotropy = sampler_state
{
	Texture = (Texture_0);
	AddressU = CLAMP;
	AddressV = CLAMP;
	MinFilter = ANISOTROPIC;
	MagFilter = ANISOTROPIC;
	MaxAnisotropy = 16;
};

sampler Sampler_1_Bilinear = sampler_state
{
	Texture = (Texture_1);
	AddressU = CLAMP;
	AddressV = CLAMP;
	MinFilter = LINEAR;
	MagFilter = LINEAR;
};

struct APP2VS_Blit
{
	float2 Pos : POSITION0;
	float2 TexCoord0 : TEXCOORD0;
};

struct VS2PS_4Tap
{
	float4 HPos : POSITION;
	float2 FilterCoords[4] : TEXCOORD0;
};

struct VS2PS_5Tap
{
	float4 HPos : POSITION;
	float2 TexCoord0 : TEXCOORD0;
	float4 FilterCoords[2] : TEXCOORD1;
};

struct VS2PS_Blit
{
	float4 HPos : POSITION;
	float2 TexCoord0 : TEXCOORD0;
};

VS2PS_Blit Blit_VS(APP2VS_Blit Input)
{
	VS2PS_Blit Output;
	Output.HPos = float4(Input.Pos.xy, 0.0, 1.0);
	Output.TexCoord0 = Input.TexCoord0;
	return Output;
}

VS2PS_Blit Blit_Custom_VS(APP2VS_Blit Input)
{
	VS2PS_Blit Output;
	Output.HPos = mul(float4(Input.Pos.xy, 0.0, 1.0), _CustomMtx);
	Output.TexCoord0 = Input.TexCoord0;
	return Output;
}

static const float2 Offsets[5] =
{
	float2(0.0, 0.0),
	float2(0.0, 1.4584295167832),
	float2(0.0, 3.4039848066734835),
	float2(0.0, 5.351805780136256),
	float2(0.0, 7.302940716034593)
};

static const float Weights[5] =
{
	0.1329807601338109,
	0.2322770777384485,
	0.13532693306504567,
	0.05115603510197893,
	0.012539291705835646
};

float4 LinearGaussianBlur(sampler2D Source, float2 TexCoord, bool IsHorizontal)
{
	float4 OutputColor = 0.0;
	float4 TotalWeights = 0.0;
	float2 PixelSize = float2(ddx(TexCoord.x), ddy(TexCoord.y));

	OutputColor += tex2D(Source, TexCoord + (Offsets[0].xy * PixelSize)) * Weights[0];
	TotalWeights += Weights[0];

	for(int i = 1; i < 5; i++)
	{
		float2 Offset = (IsHorizontal) ? Offsets[i].yx : Offsets[i].xy;
		OutputColor += tex2D(Source, TexCoord + (Offset * PixelSize)) * Weights[i];
		OutputColor += tex2D(Source, TexCoord - (Offset * PixelSize)) * Weights[i];
		TotalWeights += (Weights[i] * 2.0);
	}

	return OutputColor / TotalWeights;
}

float4 TR_OpticsBlurH_PS(VS2PS_Blit Input) : COLOR
{
	return LinearGaussianBlur(Sampler_0_Bilinear_Mirror, Input.TexCoord0, true);
}

float4 TR_OpticsBlurV_PS(VS2PS_Blit Input) : COLOR
{
	return LinearGaussianBlur(Sampler_0_Bilinear_Mirror, Input.TexCoord0, false);
}

float4 TR_OpticsMask_PS(VS2PS_Blit Input) : COLOR
{
	float2 ScreenSize = 0.0;
	ScreenSize.x = int(1.0 / abs(ddx(Input.TexCoord0.x)));
	ScreenSize.y = int(1.0 / abs(ddy(Input.TexCoord0.y)));
	float AspectRatio = ScreenSize.x / ScreenSize.y;

	float BlurAmountMod = frac(_HighPassGate) / 0.9; // used for the fade-in effect
	float Radius1 = _BlurStrength / 1000.0; // 0.2 by default (floor() isn't used for perfomance reasons)
	float Radius2 = frac(_BlurStrength); // 0.25 by default
	float Distance = length((Input.TexCoord0 - 0.5) * float2(AspectRatio, 1.0)); // get distance from the Center of the screen

	float BlurAmount = saturate((Distance - Radius1) / (Radius2 - Radius1)) * BlurAmountMod;
	float4 OutputColor = tex2D(Sampler_0_Anisotropy, Input.TexCoord0);
	return float4(OutputColor.rgb, BlurAmount); // Alpha (.a) is the mask to be composited in the pixel shader's blend operation
}

float4 TR_PassthroughBilinear_PS(VS2PS_Blit Input) : COLOR
{
	return tex2D(Sampler_0_Bilinear, Input.TexCoord0);
}

float4 TR_PassthroughAnisotropy_PS(VS2PS_Blit Input) : COLOR
{
	return tex2D(Sampler_0_Anisotropy, Input.TexCoord0);
}

float4 Dummy_PS() : COLOR
{
	return 0.0;
}

VS2PS_Blit Blit_Magnified_PS(APP2VS_Blit Input)
{
	VS2PS_Blit Output;
	Output.HPos = float4(Input.Pos.xy * 1.1, 0.0, 1.0);
	Output.TexCoord0 = Input.TexCoord0;
	return Output;
}

VS2PS_4Tap FSBMScaleDown4x4LinearFilter_VS(APP2VS_Blit Input, uniform float4 Offsets[4])
{
	VS2PS_4Tap Output;
	Output.HPos = float4(Input.Pos.xy, 0.0, 1.0);
	Output.FilterCoords[0] = Input.TexCoord0 + Offsets[0].xy;
	Output.FilterCoords[1] = Input.TexCoord0 + Offsets[1].xy;
	Output.FilterCoords[2] = Input.TexCoord0 + Offsets[2].xy;
	Output.FilterCoords[3] = Input.TexCoord0 + Offsets[3].xy;
	return Output;
}

VS2PS_5Tap Sample5_VS(APP2VS_Blit Input, uniform float Offsets[5], uniform bool Horizontal)
{
	VS2PS_5Tap Output;
	Output.HPos = float4(Input.Pos.xy, 0.0, 1.0);

	float2 VSOffset = (Horizontal) ? float2(Offsets[4], 0.0) : float2(0.0, Offsets[4]);
	Output.TexCoord0 = Input.TexCoord0 + VSOffset;

	for(int i = 0; i < 2; i++)
	{
		float2 VSOffsetA = (Horizontal) ? float2(Offsets[i * 2], 0.0) : float2(0.0, Offsets[i * 2]);
		float2 VSOffsetB = (Horizontal) ? float2(Offsets[i * 2 + 1], 0.0) : float2(0.0, Offsets[i * 2 + 1]);
		Output.FilterCoords[i].xy = Input.TexCoord0.xy + VSOffsetA;
		Output.FilterCoords[i].zw = Input.TexCoord0.xy + VSOffsetB;
	}

	return Output;
}

float4 FSBMPassthrough_PS(VS2PS_Blit Input) : COLOR
{
	return tex2D(Sampler_0_Bilinear, Input.TexCoord0);
}

float4 FSBMPassthroughSaturateAlpha_PS(VS2PS_Blit Input) : COLOR
{
	float4 OutputColor = tex2D(Sampler_0_Bilinear, Input.TexCoord0);
	OutputColor.a = 1.0f;
	return OutputColor;
}

float4 FSBMCopyOtherRGBToAlpha_PS(VS2PS_Blit Input) : COLOR
{
	float4 OutputColor = tex2D(Sampler_0_Bilinear, Input.TexCoord0);
	OutputColor.a = dot(OutputColor.rgb, 1.0 / 3.0);
	return OutputColor;
}

float4 FSBMConvertPosTo8Bit_PS(VS2PS_Blit Input) : COLOR
{
	float4 ViewPosition = tex2D(Sampler_0_Bilinear, Input.TexCoord0);
	ViewPosition /= 50.0;
	ViewPosition = ViewPosition * 0.5 + 0.5;
	return ViewPosition;
}

float4 FSBMConvertNormalTo8Bit_PS(VS2PS_Blit Input) : COLOR
{
	return normalize(tex2D(Sampler_0_Bilinear, Input.TexCoord0)) * 0.5 + 0.5;
	// return tex2D(Sampler_0_Bilinear, Input.TexCoord0).a;
}

float4 FSBMConvertShadowMapFrontTo8Bit_PS(VS2PS_Blit Input) : COLOR
{
	return tex2D(Sampler_0_Bilinear, Input.TexCoord0);
}

float4 FSBMConvertShadowMapBackTo8Bit_PS(VS2PS_Blit Input) : COLOR
{
	return -tex2D(Sampler_0_Bilinear, Input.TexCoord0);
}

float4 FSBMScaleUp4x4LinearFilter_PS(VS2PS_Blit Input) : COLOR
{
	return tex2D(Sampler_0_Bilinear, Input.TexCoord0);
}

float4 FSBMScaleDown2x2Filter_PS(VS2PS_Blit Input) : COLOR
{
	float4 OutputColor;
	OutputColor = tex2D(Sampler_0_Bilinear, Input.TexCoord0 + _ScaleDown2x2SampleOffsets[0].xy);
	OutputColor += tex2D(Sampler_0_Bilinear, Input.TexCoord0 + _ScaleDown2x2SampleOffsets[1].xy);
	OutputColor += tex2D(Sampler_0_Bilinear, Input.TexCoord0 + _ScaleDown2x2SampleOffsets[2].xy);
	OutputColor += tex2D(Sampler_0_Bilinear, Input.TexCoord0 + _ScaleDown2x2SampleOffsets[3].xy);
	return OutputColor * 0.25;
}

void FSBMScaleDown4x4Filter_PS(in VS2PS_Blit Input, out float4 OutputColor : COLOR)
{
	OutputColor = 0;
	for(int i = 0; i < 16; i++)
	{
		OutputColor += tex2D(Sampler_0_Bilinear, Input.TexCoord0 + _ScaleDown4x4SampleOffsets[i].xy) * 0.0625;
	}
}

float4 FSBMScaleDown4x4LinearFilter_PS(VS2PS_4Tap Input) : COLOR
{
	float4 OutputColor = 0.0;
	OutputColor += tex2D(Sampler_0_Bilinear, Input.FilterCoords[0].xy);
	OutputColor += tex2D(Sampler_0_Bilinear, Input.FilterCoords[1].xy);
	OutputColor += tex2D(Sampler_0_Bilinear, Input.FilterCoords[2].xy);
	OutputColor += tex2D(Sampler_0_Bilinear, Input.FilterCoords[3].xy);
	return OutputColor * 0.25;
}

void FSBMGaussianBlur5x5CheapFilter_PS(in VS2PS_Blit Input, out float4 OutputColor : COLOR)
{
	OutputColor = 0.0;
	for(int i = 0; i < 13; i++)
	{
		OutputColor += tex2D(Sampler_0_Bilinear, Input.TexCoord0 + _GaussianBlur5x5CheapSampleOffsets[i].xy) * _GaussianBlur5x5CheapSampleWeights[i];
	}
}

void FSBM_Gaussian_Blur_5x5_Cheap_Filter_Blend_PS(VS2PS_Blit Input, out float4 OutputColor : COLOR)
{
	OutputColor = 0.0;
	for(int i = 0; i < 13; i++)
	{
		OutputColor += tex2D(Sampler_0_Bilinear, Input.TexCoord0 + _GaussianBlur5x5CheapSampleOffsets[i].xy) * _GaussianBlur5x5CheapSampleWeights[i];
	}
	OutputColor.a = _BlurStrength;
}

void FSBMGaussianBlur15x15HorizontalFilter_PS(VS2PS_Blit Input, out float4 OutputColor : COLOR)
{
	OutputColor = 0.0;
	for(int i = 0; i < 15; i++)
	{
		OutputColor += tex2D(Sampler_0_Bilinear, Input.TexCoord0 + _GaussianBlur15x15HorizontalSampleOffsets[i].xy) * _GaussianBlur15x15HorizontalSampleWeights[i];
	}
}

void FSBMGaussianBlur15x15VerticalFilter_PS(VS2PS_Blit Input, out float4 OutputColor : COLOR)
{
	OutputColor = 0.0;
	for(int i = 0; i < 15; i++)
	{
		OutputColor += tex2D(Sampler_0_Bilinear, Input.TexCoord0 + _GaussianBlur15x15VerticalSampleOffsets[i].xy) * _GaussianBlur15x15VerticalSampleWeights[i];
	}
}

float4 FSBMGrowablePoisson13Filter_PS(VS2PS_Blit Input) : COLOR
{
	float4 OutputColor = 0.0;
	float Samples = 1.0;

	OutputColor = tex2D(Sampler_0_Bilinear, Input.TexCoord0);

	for(int i = 0; i < 11; i++)
	{
		// float4 V = tex2D(Sampler_0_Bilinear, Input.TexCoord0 + _GrowablePoisson13SampleOffsets[i]);
		float4 V = tex2D(Sampler_0_Bilinear, Input.TexCoord0 + _GrowablePoisson13SampleOffsets[i].xy * 0.1 * OutputColor.a);
		if(V.a > 0)
		{
			OutputColor.rgb += V;
			Samples += 1.0;
		}
	}

	return OutputColor / Samples;
}

float4 FSBMGrowablePoisson13AndDilationFilter_PS(VS2PS_Blit Input) : COLOR
{
	float4 Center = tex2D(Sampler_0_Bilinear, Input.TexCoord0);

	float4 OutputColor = 0.0;
	OutputColor = (Center.a > 0) ? float4(Center.rgb, 1.0) : OutputColor;

	for(int i = 0; i < 11; i++)
	{
		float Scale = Center.a * 3.0;

		if(Scale == 0)
		{
			Scale = 1.5;
		}

		float4 V = tex2D(Sampler_0_Bilinear, Input.TexCoord0 + _GrowablePoisson13SampleOffsets[i].xy*Scale);

		if(V.a > 0)
		{
			OutputColor.rgb += V.rgb;
			OutputColor.a += 1.0;
		}
	}

	return OutputColor / OutputColor.a;
}

float4 FSBMGlowFilter_PS(VS2PS_5Tap Input, uniform float Weights[5], uniform bool Horizontal) : COLOR
{
	float4 OutputColor = Weights[0] * tex2D(Sampler_0_Bilinear, Input.FilterCoords[0].xy);
	OutputColor += Weights[1] * tex2D(Sampler_0_Bilinear, Input.FilterCoords[0].zw);
	OutputColor += Weights[2] * tex2D(Sampler_0_Bilinear, Input.FilterCoords[1].xy);
	OutputColor += Weights[3] * tex2D(Sampler_0_Bilinear, Input.FilterCoords[1].zw);
	OutputColor += Weights[4] * tex2D(Sampler_0_Bilinear, Input.TexCoord0);
	return OutputColor;
}

float4 FSBMHighPassFilter_PS(VS2PS_Blit Input) : COLOR
{
	float4 OutputColor = tex2D(Sampler_0_Bilinear, Input.TexCoord0);
	OutputColor -= _HighPassGate;
	return max(OutputColor, 0.0);
}

float4 FSBMHighPassFilterFade_PS(VS2PS_Blit Input) : COLOR
{
	float4 OutputColor = tex2D(Sampler_0_Bilinear, Input.TexCoord0);
	OutputColor.rgb = saturate(OutputColor.rgb - _HighPassGate);
	OutputColor.a = _BlurStrength;
	return OutputColor;
}

float4 FSBMClear_PS(VS2PS_Blit Input) : COLOR
{
	return 0.0;
}

float4 FSBMExtractGlowFilter_PS(VS2PS_Blit Input) : COLOR
{
	float4 OutputColor = tex2D(Sampler_0_Bilinear, Input.TexCoord0);
	OutputColor.rgb = OutputColor.a;
	OutputColor.a = 1.0;
	return OutputColor;
}

float4 FSBMExtractHDRFilterFade_PS(VS2PS_Blit Input) : COLOR
{
	float4 OutputColor = tex2D(Sampler_0_Bilinear, Input.TexCoord0);
	OutputColor.rgb = saturate(OutputColor.a - _HighPassGate);
	OutputColor.a = _BlurStrength;
	return OutputColor;
}

float4 FSBMLuminancePlusBrightPassFilter_PS(VS2PS_Blit Input) : COLOR
{
	float4 OutputColor = tex2D(Sampler_0_Bilinear, Input.TexCoord0) * _HighPassGate;
	// float luminance = dot(OutputColor, float3(0.299f, 0.587f, 0.114f));
	return OutputColor;
}

float4 FSBMBloomFilter_PS(VS2PS_5Tap Input, uniform bool Is_Blur) : COLOR
{
	float4 OutputColor = 0.0;
	OutputColor.a = (Is_Blur) ? _BlurStrength : OutputColor.a;

	OutputColor.rgb += tex2D(Sampler_0_Bilinear, Input.TexCoord0.xy);

	for(int i = 0; i < 2; i++)
	{
		OutputColor.rgb += tex2D(Sampler_0_Bilinear, Input.FilterCoords[i].xy);
		OutputColor.rgb += tex2D(Sampler_0_Bilinear, Input.FilterCoords[i].zw);
	}

	OutputColor.rgb /= 5.0;
	return OutputColor;
}

float4 FSBMScaleUpBloomFilter_PS(VS2PS_Blit Input) : COLOR
{
	float Offset = 0.01;
	// We can use a blur for this
	float4 Close = tex2D(Sampler_0_Bilinear, Input.TexCoord0);
	return Close;
}

float4 FSBMBlur_PS(VS2PS_Blit Input) : COLOR
{
	return float4(tex2D(Sampler_0_Bilinear, Input.TexCoord0).rgb, _BlurStrength);
}

//
//	Techniques
//

technique Blit
{
	pass FSBMPassThrough
	{
		ZEnable = FALSE;
		AlphaBlendEnable = FALSE;
		StencilEnable = FALSE;
		AlphaTestEnable = FALSE;
		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 FSBMPassthrough_PS();
	}

	pass FSBMBlend
	{
		ZEnable = FALSE;
		AlphaBlendEnable = TRUE;
		StencilEnable = FALSE;
		AlphaTestEnable = FALSE;
		SrcBlend = SRCALPHA;
		DestBlend = INVSRCALPHA;

		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 FSBMPassthrough_PS();
	}

	pass FSBMConvertPosTo8Bit
	{
		ZEnable = FALSE;
		AlphaBlendEnable = FALSE;
		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 FSBMConvertPosTo8Bit_PS();
	}

	pass FSBMConvertNormalTo8Bit
	{
		ZEnable = FALSE;
		AlphaBlendEnable = FALSE;
		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 FSBMConvertNormalTo8Bit_PS();
	}

	pass FSBMConvertShadowMapFrontTo8Bit
	{
		ZEnable = FALSE;
		AlphaBlendEnable = FALSE;
		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 FSBMConvertShadowMapFrontTo8Bit_PS();
	}

	pass FSBMConvertShadowMapBackTo8Bit
	{
		ZEnable = FALSE;
		AlphaBlendEnable = FALSE;
		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 FSBMConvertShadowMapBackTo8Bit_PS();
	}

	pass FSBMScaleUp4x4LinearFilter
	{
		ZEnable = FALSE;
		AlphaBlendEnable = FALSE;
		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 FSBMScaleUp4x4LinearFilter_PS();
	}

	pass FSBMScaleDown2x2Filter
	{
		ZEnable = FALSE;
		AlphaBlendEnable = FALSE;
		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 FSBMScaleDown2x2Filter_PS();
	}

	pass FSBMScaleDown4x4Filter
	{
		ZEnable = FALSE;
		AlphaBlendEnable = FALSE;
		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 FSBMScaleDown4x4Filter_PS();
	}

	pass FSBMScaleDown4x4LinearFilter // pass 9, tinnitus
	{
		ZEnable = FALSE;
		AlphaBlendEnable = FALSE;
		VertexShader = compile vs_3_0 FSBMScaleDown4x4LinearFilter_VS(_ScaleDown4x4LinearSampleOffsets); // Blit_VS();
		PixelShader = compile ps_3_0 FSBMScaleDown4x4LinearFilter_PS();
	}

	pass FSBMGaussianBlur5x5CheapFilter
	{
		ZEnable = FALSE;
		AlphaBlendEnable = FALSE;
		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 FSBMGaussianBlur5x5CheapFilter_PS();
	}

	pass FSBMGaussianBlur15x15HorizontalFilter
	{
		ZEnable = FALSE;
		AlphaBlendEnable = FALSE;
		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 FSBMGaussianBlur15x15HorizontalFilter_PS();
	}

	pass FSBMGaussianBlur15x15VerticalFilter
	{
		ZEnable = FALSE;
		AlphaBlendEnable = FALSE;
		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 FSBMGaussianBlur15x15VerticalFilter_PS();
	}

	pass FSBMGrowablePoisson13Filter
	{
		ZEnable = FALSE;
		AlphaBlendEnable = FALSE;
		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 FSBMGrowablePoisson13Filter_PS();
	}

	pass FSBMGrowablePoisson13AndDilationFilter
	{
		ZEnable = FALSE;
		AlphaBlendEnable = FALSE;
		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 FSBMGrowablePoisson13AndDilationFilter_PS();
	}

	pass FSBMScaleUpBloomFilter
	{
		ZEnable = FALSE;
		AlphaBlendEnable = FALSE;
		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 FSBMScaleUpBloomFilter_PS();
	}

	pass FSBMPassThroughSaturateAlpha
	{
		ZEnable = FALSE;
		AlphaBlendEnable = FALSE;
		StencilEnable = FALSE;
		AlphaTestEnable = FALSE;
		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 FSBMPassthroughSaturateAlpha_PS();
	}

	pass FSBMCopyOtherRGBToAlpha
	{
		ZEnable = FALSE;
		AlphaBlendEnable = FALSE;
		StencilEnable = FALSE;
		AlphaTestEnable = FALSE;
		ColorWriteEnable = ALPHA;

		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 FSBMCopyOtherRGBToAlpha_PS();
	}

	// X-Pack additions
	pass FSBMPassThroughBilinear
	{
		ZEnable = FALSE;
		AlphaBlendEnable = FALSE;
		StencilEnable = FALSE;
		AlphaTestEnable = FALSE;
		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 TR_PassthroughBilinear_PS();
	}

	pass FSBMPassThroughBilinearAdditive
	{
		/*
			ZEnable = FALSE;
			AlphaBlendEnable = TRUE;
			SrcBlend = ONE;
			DestBlend = ONE;
			StencilEnable = FALSE;
			AlphaTestEnable = FALSE;
		*/

		// VertexShader = compile vs_3_0 Blit_VS();
		// PixelShader = compile ps_3_0 FSBMPassthrough_PS();

		/*
			ZEnable = FALSE;
			AlphaBlendEnable = FALSE;
			StencilEnable = FALSE;
			AlphaTestEnable = FALSE;
		*/

		ZEnable = FALSE;
		AlphaBlendEnable = TRUE;
		SrcBlend = ZERO;
		DestBlend = ONE;
		StencilEnable = FALSE;
		AlphaTestEnable = FALSE;
		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 TR_PassthroughBilinear_PS();
	}

	pass FSMBlur
	{
		VertexShader = NULL;
		PixelShader = NULL;
	}

	pass FSBMScaleUp4x4LinearFilterAdditive
	{
		VertexShader = NULL;
		PixelShader = NULL;
	}

	pass FSBMGaussianBlur5x5CheapFilterBlend
	{
		VertexShader = NULL;
		PixelShader = NULL;
	}

	pass FSBMGaussianBlur5x5CheapFilterAdditive
	{
		VertexShader = NULL;
		PixelShader = NULL;
	}

	pass FSBMScaleUpBloomFilterAdditive
	{
		VertexShader = NULL;
		PixelShader = NULL;
	}

	pass FSBMGlowHorizontalFilter // pass 25
	{
		ZEnable = FALSE;
		AlphaBlendEnable = FALSE;
		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 TR_OpticsBlurH_PS();
	}

	pass FSBMGlowVerticalFilter // pass 26
	{
		ZEnable = FALSE;
		AlphaBlendEnable = FALSE;
		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 TR_OpticsBlurV_PS();
	}

	pass FSBMGlowVerticalFilterAdditive
	{
		VertexShader = NULL;
		PixelShader = NULL;
	}

	pass FSBMHighPassFilter
	{
		VertexShader = NULL;
		PixelShader = NULL;
	}

	pass FSBMHighPassFilterFade  // pass 29
	{
		ZEnable = FALSE;
		AlphaBlendEnable = FALSE;
		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 TR_PassthroughBilinear_PS();
	}

	pass FSBMExtractGlowFilter
	{
		VertexShader = NULL;
		PixelShader = NULL;
	}

	pass FSBMExtractHDRFilterFade
	{
		VertexShader = NULL;
		PixelShader = NULL;
	}

	pass FSBMClearAlpha
	{
		ZEnable = FALSE;
		AlphaBlendEnable = FALSE;
		StencilEnable = FALSE;
		AlphaTestEnable = FALSE;
		ColorWriteEnable = ALPHA;

		VertexShader = compile vs_3_0 Blit_Magnified_PS(); // is this needed? -mosq
		PixelShader = compile ps_3_0 FSBMClear_PS();
	}

	pass FSBMAdditive
	{
		VertexShader = NULL;
		PixelShader = NULL;
	}

	pass FSBMAdditiveBilinear  // pass 34
	{
		ZEnable = FALSE;
		AlphaBlendEnable = TRUE;
		StencilEnable = FALSE;
		AlphaTestEnable = FALSE;
		BlendOp = ADD;
		SrcBlend = SRCALPHA;
		DestBlend = INVSRCALPHA;
		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 TR_OpticsMask_PS();
	}

	pass FSBMBloomHorizFilter // pass 35
	{
		ZEnable = FALSE;
		AlphaBlendEnable = FALSE;
		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 TR_PassthroughBilinear_PS();
	}

	pass FSBMBloomHorizFilterAdditive
	{
		VertexShader = NULL;
		PixelShader = NULL;
	}

	pass FSBMBloomVertFilter // pass 37
	{
		ZEnable = FALSE;
		AlphaBlendEnable = FALSE;
		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 TR_PassthroughBilinear_PS();
	}

	pass FSBMBloomVertFilterAdditive
	{
		VertexShader = NULL;
		PixelShader = NULL;
	}

	pass FSBMBloomVertFilterBlur
	{
		VertexShader = NULL;
		PixelShader = NULL;
	}

	pass FSBMBloomVertFilterAdditiveBlur
	{
		VertexShader = NULL;
		PixelShader = NULL;
	}

	pass FSBMLuminancePlusBrightPassFilter
	{
		VertexShader = NULL;
		PixelShader = NULL;
	}

	pass FSBMScaleDown4x4LinearFilterHorizontal // pass 42
	{
		ZEnable = FALSE;
		AlphaBlendEnable = FALSE;
		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 TR_PassthroughAnisotropy_PS();
	}

	pass FSBMScaleDown4x4LinearFilterVertical // pass 43
	{
		ZEnable = FALSE;
		AlphaBlendEnable = FALSE;
		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 TR_PassthroughAnisotropy_PS();
	}

	pass FSBMClear
	{
		ZEnable = FALSE;
		AlphaBlendEnable = FALSE;
		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 FSBMClear_PS();
	}

	pass FSBMBlendCustom
	{
		ZEnable = FALSE;
		AlphaBlendEnable = TRUE;
		StencilEnable = FALSE;
		AlphaTestEnable = FALSE;
		SrcBlend = SRCALPHA;
		DestBlend = INVSRCALPHA;

		VertexShader = compile vs_3_0 Blit_Custom_VS();
		PixelShader = compile ps_3_0 FSBMPassthrough_PS();
	}

}

float4 StencilGather_PS(VS2PS_Blit Input) : COLOR
{
	return _dwordStencilRef / 255.0;
}

float4 StencilMap_PS(VS2PS_Blit Input) : COLOR
{
	float4 Stencil = tex2D(Sampler_0_Bilinear, Input.TexCoord0);
	return tex1D(Sampler_1_Bilinear, Stencil.x / 255.0);
}

technique StencilPasses
{
	pass StencilGather
	{
		ZEnable = FALSE;
		AlphaBlendEnable = FALSE;
		AlphaTestEnable = FALSE;

		StencilEnable = TRUE;
		StencilRef = (_dwordStencilRef);
		StencilFunc = EQUAL;
		StencilFail = KEEP;
		StencilZFail = KEEP;
		StencilPass = KEEP;

		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 StencilGather_PS();
	}

	pass StencilMap
	{
		ZEnable = FALSE;
		AlphaBlendEnable = FALSE;
		AlphaTestEnable = FALSE;
		StencilEnable = FALSE;

		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 StencilMap_PS();
	}
}

technique ResetStencilCuller
{
	pass NV4X
	{
		ZEnable = TRUE;
		ZWriteEnable = FALSE;
		ZFunc = ALWAYS;

		AlphaBlendEnable = FALSE;
		AlphaTestEnable = FALSE;
		ColorWriteEnable = 0;
		ColorWriteEnable1 = 0;
		ColorWriteEnable2 = 0;
		ColorWriteEnable3 = 0;

		StencilEnable = TRUE;
		StencilRef = (_dwordStencilRef);
		StencilMask = 0xFF;
		StencilWriteMask = 0xFF;
		StencilFunc = EQUAL;
		StencilFail = KEEP;
		StencilZFail = KEEP;
		StencilPass = (_dwordStencilPass);
		TwoSidedStencilMode = FALSE;

		VertexShader = compile vs_3_0 Blit_VS();
		PixelShader = compile ps_3_0 Dummy_PS();
	}
}
