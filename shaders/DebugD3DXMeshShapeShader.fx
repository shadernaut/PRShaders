
/*
	Description: Renders shapes to debug collision mesh, culling, etc.
*/

#include "shaders/RealityGraphics.fxh"

float4x4 _WorldViewProj : WorldViewProjection;
float4x4 _World : World;

string Category = "Effects\\Lighting";

uniform texture Tex0 : TEXLAYER0;
sampler SampleTex0 = sampler_state
{
	Texture = (Tex0);
	MinFilter = ANISOTROPIC;
	MagFilter = ANISOTROPIC;
	MipFilter = LINEAR;
	AddressU = WRAP;
	AddressV = WRAP;
};

float _TextureScale : TEXTURESCALE;

float4 _LightDir = { 1.0, 0.0, 0.0, 1.0 }; // Light Direction
float4 _MaterialAmbient : MATERIALAMBIENT = { 0.5, 0.5, 0.5, 1.0 };
float4 _MaterialDiffuse : MATERIALDIFFUSE = { 1.0, 1.0, 1.0, 1.0 };

// float4 _Alpha : BLENDALPHA = { 1.0, 1.0, 1.0, 1.0 };

float4 _ConeSkinValues : CONESKINVALUES;

struct APP2VS
{
	float4 Pos : POSITION;
	float3 Normal : NORMAL;
	float4 Color : COLOR;
};

struct VS2PS
{
	float4 HPos : POSITION;
	float4 Pos : TEXCOORD0;
};

struct PS2FB
{
	float4 Color : COLOR;
	#if defined(LOG_DEPTH)
		float Depth : DEPTH;
	#endif
};

// Clamped N.L
float3 GetDotNL(float3 Normal, uniform float3 LightDir)
{
	return saturate(dot(Normal, LightDir.xyz));
}

/*
	Basic debug shaders
*/

struct VS2PS_Basic
{
	float4 HPos : POSITION;
	float4 Pos : TEXCOORD0;
	float3 Normal : TEXCOORD1;
};

VS2PS_Basic Debug_Basic_VS(APP2VS Input)
{
	VS2PS_Basic Output = (VS2PS_Basic)0;

	float3 Pos = mul(Input.Pos, _World);
	Output.HPos = mul(float4(Pos.xyz, 1.0), _WorldViewProj);
	Output.Pos = Output.HPos;
	#if defined(LOG_DEPTH)
		Output.Pos.w = Output.HPos.w + 1.0; // Output depth
	#endif

	Output.Normal = Input.Normal;

	return Output;
}

PS2FB Debug_Basic_1_PS(VS2PS_Basic Input)
{
	PS2FB Output = (PS2FB)0;

	float4 Ambient = _MaterialAmbient;
	float3 Diffuse = GetDotNL(Input.Normal, _LightDir.xyz) * _MaterialDiffuse.rgb;

	Output.Color = float4(Ambient.rgb + Diffuse, Ambient.a);

	#if defined(LOG_DEPTH)
		Output.Depth = ApplyLogarithmicDepth(Input.Pos.w);
	#endif

	return Output;
}

PS2FB Debug_Basic_2_PS(VS2PS_Basic Input)
{
	PS2FB Output = (PS2FB)0;

	Output.Color = float4(_MaterialAmbient.rgb, 0.3);

	#if defined(LOG_DEPTH)
		Output.Depth = ApplyLogarithmicDepth(Input.Pos.w);
	#endif

	return Output;
}

PS2FB Debug_Object_PS(VS2PS Input)
{
	PS2FB Output = (PS2FB)0;

	Output.Color = _MaterialAmbient;

	#if defined(LOG_DEPTH)
		Output.Depth = ApplyLogarithmicDepth(Input.Pos.w);
	#endif

	return Output;
}

technique t0
<
	int DetailLevel = DLHigh+DLNormal+DLLow+DLAbysmal;
	int Compatibility = CMPR300+CMPNV2X;
	int Declaration[] =
	{
		// StreamNo, DataType, Usage, UsageIdx
		{ 0, D3DDECLTYPE_FLOAT3, D3DDECLUSAGE_POSITION, 0 },
		{ 0, D3DDECLTYPE_FLOAT3, D3DDECLUSAGE_NORMAL, 0 },
		DECLARATION_END	// End macro
	};
>
{
	pass Pass0
	{
		AlphaBlendEnable = TRUE;
		SrcBlend = SRCALPHA;
		DestBlend = INVSRCALPHA;

		VertexShader = compile vs_3_0 Debug_Basic_VS();
		PixelShader = compile ps_3_0 Debug_Basic_1_PS();
	}
}

/*
	Debug occluder shaders
*/

VS2PS Debug_Occluder_VS(APP2VS Input)
{
	VS2PS Output = (VS2PS)0;

	float4 WorldPos = mul(Input.Pos, _World);
	Output.HPos = mul(WorldPos, _WorldViewProj);
	Output.Pos = Output.HPos;
	#if defined(LOG_DEPTH)
		Output.Pos.w = Output.HPos.w + 1.0; // Output depth
	#endif

	return Output;
}

PS2FB Debug_Occluder_PS(VS2PS Input)
{
	PS2FB Output = (PS2FB)0;

	Output.Color = float4(1.0, 0.5, 0.5, 0.5);

	#if defined(LOG_DEPTH)
		Output.Depth = ApplyLogarithmicDepth(Input.Pos.w);
	#endif

	return Output;
}

technique occluder
<
	int DetailLevel = DLHigh+DLNormal+DLLow+DLAbysmal;
	int Compatibility = CMPR300+CMPNV2X;
	int Declaration[] =
	{
		// StreamNo, DataType, Usage, UsageIdx
		{ 0, D3DDECLTYPE_FLOAT3, D3DDECLUSAGE_POSITION, 0 },
		{ 0, D3DDECLTYPE_FLOAT3, D3DDECLUSAGE_NORMAL, 0 },
		DECLARATION_END	// End macro
	};
>
{
	pass Pass0
	{
		AlphaBlendEnable = TRUE;
		SrcBlend = SRCALPHA;
		DestBlend = INVSRCALPHA;

		ZWriteEnable = TRUE;
		ZEnable = TRUE;
		ZFunc = LESSEQUAL;

		VertexShader = compile vs_3_0 Debug_Occluder_VS();
		PixelShader = compile ps_3_0 Debug_Occluder_PS();
	}
}

/*
	Debug editor shaders
*/

VS2PS Debug_Editor_VS(APP2VS Input)
{
	VS2PS Output = (VS2PS)0;

	float2 RadScale = lerp(_ConeSkinValues.x, _ConeSkinValues.y, Input.Pos.z + 0.5);
	float4 WorldPos = mul(Input.Pos * float4(RadScale, 1.0, 1.0), _World);

	Output.HPos = mul(WorldPos, _WorldViewProj);
	Output.Pos = Output.HPos;
	#if defined(LOG_DEPTH)
		Output.Pos.w = Output.HPos.w + 1.0; // Output depth
	#endif

	return Output;
}

PS2FB Debug_Editor_PS(VS2PS Input, uniform float AmbientColorFactor = 1.0)
{
	PS2FB Output = (PS2FB)0;

	Output.Color = float4(_MaterialAmbient.rgb * AmbientColorFactor, _MaterialAmbient.a);

	#if defined(LOG_DEPTH)
		Output.Depth = ApplyLogarithmicDepth(Input.Pos.w);
	#endif

	return Output;
}

technique EditorDebug
<
	int DetailLevel = DLHigh+DLNormal+DLLow+DLAbysmal;
	int Compatibility = CMPR300+CMPNV2X;
>
{
	pass Pass0
	{
		CullMode = NONE;
		ShadeMode = FLAT;
		FillMode = SOLID;

		AlphaBlendEnable = TRUE;
		SrcBlend = SRCALPHA;
		DestBlend = INVSRCALPHA;

		ZWriteEnable = 1;
		ZEnable = TRUE;
		ZFunc = LESSEQUAL;

		VertexShader = compile vs_3_0 Debug_Editor_VS();
		PixelShader = compile ps_3_0 Debug_Editor_PS();
	}

	pass Pass1
	{
		CullMode = CW;

		ZEnable = TRUE;
		FillMode = WIREFRAME;

		VertexShader = compile vs_3_0 Debug_Editor_VS();
		PixelShader = compile ps_3_0 Debug_Editor_PS(0.5);
	}
}

/*
	Debug occluder shaders
*/

struct VS2PS_CollisionMesh
{
	float4 HPos : POSITION;
	float4 Pos : TEXCOORD0;
	float3 Normal : TEXCOORD1;
};

VS2PS_CollisionMesh Debug_CollisionMesh_VS(APP2VS Input)
{
	VS2PS_CollisionMesh Output = (VS2PS_CollisionMesh)0;

	float3 Pos = mul(Input.Pos, _World);
	Output.HPos = mul(float4(Pos.xyz, 1.0), _WorldViewProj);
	Output.Pos = Output.HPos;
	#if defined(LOG_DEPTH)
		Output.Pos.w = Output.HPos.w + 1.0; // Output depth
	#endif

	Output.Normal = Input.Normal;

	return Output;
}

PS2FB Debug_CollisionMesh_PS(VS2PS_CollisionMesh Input, uniform float MaterialFactor = 1.0)
{
	PS2FB Output = (PS2FB)0;

	float DotNL = GetDotNL(Input.Normal, float3(-1.0, -1.0, 1.0));
	float3 Ambient = (_MaterialAmbient.rgb * MaterialFactor) + 0.1;
	float3 Diffuse = DotNL * (_MaterialDiffuse.rgb * MaterialFactor);

	Output.Color = float4(Ambient + Diffuse, 0.8);

	#if defined(LOG_DEPTH)
		Output.Depth = ApplyLogarithmicDepth(Input.Pos.w);
	#endif

	return Output;
}

technique collisionMesh
<
	int DetailLevel = DLHigh+DLNormal+DLLow+DLAbysmal;
	int Compatibility = CMPR300+CMPNV2X;
>
{
	pass Pass0
	{
		CullMode = NONE;
		ShadeMode = FLAT;
		DepthBias = -0.00001;

		AlphaBlendEnable = TRUE;
		SrcBlend = SRCALPHA;
		DestBlend = INVSRCALPHA;

		ZWriteEnable = 1;
		ZEnable = TRUE;
		ZFunc = LESSEQUAL;

		VertexShader = compile vs_3_0 Debug_CollisionMesh_VS();
		PixelShader = compile ps_3_0 Debug_CollisionMesh_PS();
	}

	pass Pass1
	{
		DepthBias = -0.000018;
		FillMode = WIREFRAME;

		AlphaBlendEnable = TRUE;
		SrcBlend = SRCALPHA;
		DestBlend = INVSRCALPHA;

		ZEnable = TRUE;
		ZWriteEnable = 1;

		VertexShader = compile vs_3_0 Debug_CollisionMesh_VS();
		PixelShader = compile ps_3_0 Debug_CollisionMesh_PS(0.5);
	}

	pass Pass2
	{
		FillMode = SOLID;
	}
}

technique marked
<
	int DetailLevel = DLHigh+DLNormal+DLLow+DLAbysmal;
	int Compatibility = CMPR300+CMPNV2X;
	int Declaration[] =
	{
		// StreamNo, DataType, Usage, UsageIdx
		{ 0, D3DDECLTYPE_FLOAT3, D3DDECLUSAGE_POSITION, 0 },
		{ 0, D3DDECLTYPE_FLOAT3, D3DDECLUSAGE_NORMAL, 0 },
		DECLARATION_END	// End macro
	};
>
{
	pass Pass0
	{
		AlphaBlendEnable = TRUE;
		SrcBlend = SRCALPHA;
		DestBlend = INVSRCALPHA;

		VertexShader = compile vs_3_0 Debug_Basic_VS();
		PixelShader = compile ps_3_0 Debug_Basic_1_PS();
	}
}

technique gamePlayObject
<
	int DetailLevel = DLHigh+DLNormal+DLLow+DLAbysmal;
	int Compatibility = CMPR300+CMPNV2X;
	int Declaration[] =
	{
		// StreamNo, DataType, Usage, UsageIdx
		{ 0, D3DDECLTYPE_FLOAT3, D3DDECLUSAGE_POSITION, 0 },
		{ 0, D3DDECLTYPE_FLOAT3, D3DDECLUSAGE_NORMAL, 0 },
		DECLARATION_END	// End macro
	};
>
{
	pass Pass0
	{
		AlphaBlendEnable = TRUE;
		SrcBlend = SRCALPHA;
		DestBlend = INVSRCALPHA;

		ZEnable = TRUE;

		VertexShader = compile vs_3_0 Debug_Basic_VS();
		PixelShader = compile ps_3_0 Debug_Basic_2_PS();
	}
}

technique bounding
<
	int DetailLevel = DLHigh+DLNormal+DLLow+DLAbysmal;
	int Compatibility = CMPR300+CMPNV2X;
	int Declaration[] =
	{
		// StreamNo, DataType, Usage, UsageIdx
		{ 0, D3DDECLTYPE_FLOAT3, D3DDECLUSAGE_POSITION, 0 },
		{ 0, D3DDECLTYPE_FLOAT3, D3DDECLUSAGE_NORMAL, 0 },
		DECLARATION_END	// End macro
	};
>
{
	pass Pass0
	{
		AlphaBlendEnable = FALSE;
		SrcBlend = SRCALPHA;
		DestBlend = INVSRCALPHA;

		ZWriteEnable = 0;
		ZEnable = FALSE;

		CullMode = NONE;
		FillMode = WIREFRAME;

		VertexShader = compile vs_3_0 Debug_Basic_VS();
		PixelShader = compile ps_3_0 Debug_Basic_2_PS();
	}
}

/*
	Debug grid shaders
*/

struct VS2PS_Grid
{
	float4 HPos : POSITION;
	float3 Tex0 : TEXCOORD0;
	float3 Normal : TEXCOORD1;
};

VS2PS_Grid Debug_Grid_VS(APP2VS Input)
{
	VS2PS_Grid Output = (VS2PS_Grid)0;

	float3 Pos = mul(Input.Pos, _World);
	Output.HPos = mul(float4(Pos.xyz, 1.0), _WorldViewProj);

	Output.Tex0.xy = (Input.Pos.xz * 0.5) + 0.5;
	Output.Tex0.xy *= _TextureScale;
	#if defined(LOG_DEPTH)
		Output.Tex0.z = Output.HPos.w + 1.0; // Output depth
	#endif

	Output.Normal = Input.Normal;

	return Output;
}

PS2FB Debug_Grid_PS(VS2PS_Grid Input)
{
	PS2FB Output = (PS2FB)0;

	float DotNL = GetDotNL(Input.Normal, _LightDir.xyz);
	float3 Lighting = _MaterialAmbient.rgb + (DotNL * _MaterialDiffuse.rgb);

	float4 Tex = tex2D(SampleTex0, Input.Tex0.xy);
	// float4 OutputColor = float4(Tex.rgb * Lighting, _MaterialDiffuse.a);
	float4 OutputColor = float4(Tex.rgb * Lighting, 1.0 - Tex.b);

	Output.Color = OutputColor;

	#if defined(LOG_DEPTH)
		Output.Depth = ApplyLogarithmicDepth(Input.Tex0.z);
	#endif

	return Output;
}

technique grid
<
	int DetailLevel = DLHigh+DLNormal+DLLow+DLAbysmal;
	int Compatibility = CMPR300+CMPNV2X;
	int Declaration[] =
	{
		// StreamNo, DataType, Usage, UsageIdx
		{ 0, D3DDECLTYPE_FLOAT3, D3DDECLUSAGE_POSITION, 0 },
		{ 0, D3DDECLTYPE_FLOAT3, D3DDECLUSAGE_NORMAL, 0 },
		DECLARATION_END	// End macro
	};
>
{
	pass Pass0
	{
		AlphaBlendEnable = TRUE;
		SrcBlend = SRCALPHA;
		DestBlend = INVSRCALPHA;

		VertexShader = compile vs_3_0 Debug_Grid_VS();
		PixelShader = compile ps_3_0 Debug_Grid_PS();
	}
}

/*
	Debug SpotLight shaders
*/

VS2PS Debug_SpotLight_VS(APP2VS Input)
{
	VS2PS Output = (VS2PS)0;

	float4 Pos = Input.Pos;
	Pos.z += 0.5;
	float RadScale = lerp(_ConeSkinValues.x, _ConeSkinValues.y, Pos.z);
	Pos.xy *= RadScale;
	Pos = mul(Pos, _World);

	Output.HPos = mul(Pos, _WorldViewProj);
	Output.Pos = Output.HPos;
	#if defined(LOG_DEPTH)
		Output.Pos.w = Output.HPos.w + 1.0; // Output depth
	#endif

	return Output;
}

technique spotlight
<
	int Declaration[] =
	{
		// StreamNo, DataType, Usage, UsageIdx
		{ 0, D3DDECLTYPE_FLOAT3, D3DDECLUSAGE_POSITION, 0 },
		{ 0, D3DDECLTYPE_FLOAT3, D3DDECLUSAGE_NORMAL, 0 },
		DECLARATION_END	// End macro
	};
>
{
	pass Pass0
	{
		CullMode = NONE;

		ColorWriteEnable = 0;

		AlphaBlendEnable = FALSE;

		ZFunc = LESSEQUAL;
		ZWriteEnable = TRUE;

		VertexShader = compile vs_3_0 Debug_SpotLight_VS();
		PixelShader = compile ps_3_0 Debug_Object_PS();
	}

	pass Pass1
	{
		ColorWriteEnable = Red|Blue|Green|Alpha;

		AlphaBlendEnable = TRUE;
		SrcBlend = SRCALPHA;
		DestBlend = INVSRCALPHA;

		ZFunc = EQUAL;
		ZWriteEnable = FALSE;

		VertexShader = compile vs_3_0 Debug_SpotLight_VS();
		PixelShader = compile ps_3_0 Debug_Object_PS();
	}
}

/*
	Debug PivotBox shaders
*/

VS2PS Debug_PivotBox_VS(APP2VS Input)
{
	VS2PS Output = (VS2PS)0;

	float4 Pos = mul(Input.Pos, _World);
	Output.HPos = mul(Pos, _WorldViewProj);
	Output.Pos = Output.HPos;
	#if defined(LOG_DEPTH)
		Output.Pos.w = Output.HPos.w + 1.0; // Output depth
	#endif

	return Output;
}

VS2PS Debug_Pivot_VS(APP2VS Input)
{
	VS2PS Output = (VS2PS)0;

	float4 Pos = Input.Pos;
	float RadScale = lerp(_ConeSkinValues.x, _ConeSkinValues.y, Pos.z + 0.5);
	Pos.xy *= RadScale;
	Pos = mul(Pos, _World);

	Output.HPos = mul(Pos, _WorldViewProj);
	Output.Pos = Output.HPos;
	#if defined(LOG_DEPTH)
		Output.Pos.w = Output.HPos.w + 1.0; // Output depth
	#endif

	return Output;
}

technique pivotBox
<
	int Declaration[] =
	{
		// StreamNo, DataType, Usage, UsageIdx
		{ 0, D3DDECLTYPE_FLOAT3, D3DDECLUSAGE_POSITION, 0 },
		{ 0, D3DDECLTYPE_FLOAT3, D3DDECLUSAGE_NORMAL, 0 },
		DECLARATION_END	// End macro
	};
>
{
	pass Pass0
	{
		AlphaBlendEnable = TRUE;
		SrcBlend = SRCALPHA;
		DestBlend = INVSRCALPHA;

		ZWriteEnable = 0;
		ZEnable = FALSE;

		VertexShader = compile vs_3_0 Debug_PivotBox_VS();
		PixelShader = compile ps_3_0 Debug_Object_PS();
	}

	pass Pass1
	{
		ColorWriteEnable = Red|Blue|Green|Alpha;

		AlphaBlendEnable = TRUE;
		SrcBlend = SRCALPHA;
		DestBlend = INVSRCALPHA;

		ZFunc = EQUAL;
		ZWriteEnable = FALSE;

		VertexShader = compile vs_3_0 Debug_PivotBox_VS();
		PixelShader = compile ps_3_0 Debug_Object_PS();
	}
}

technique pivot
<
	int Declaration[] =
	{
		// StreamNo, DataType, Usage, UsageIdx
		{ 0, D3DDECLTYPE_FLOAT3, D3DDECLUSAGE_POSITION, 0 },
		{ 0, D3DDECLTYPE_FLOAT3, D3DDECLUSAGE_NORMAL, 0 },
		DECLARATION_END	// End macro
	};
>
{
	pass Pass0
	{
		AlphaBlendEnable = TRUE;
		SrcBlend = SRCALPHA;
		DestBlend = INVSRCALPHA;

		ZWriteEnable = 0;
		ZEnable = FALSE;

		VertexShader = compile vs_3_0 Debug_Pivot_VS();
		PixelShader = compile ps_3_0 Debug_Object_PS();
	}

	pass Pass1
	{
		ColorWriteEnable = Red|Blue|Green|Alpha;

		AlphaBlendEnable = TRUE;
		SrcBlend = SRCALPHA;
		DestBlend = INVSRCALPHA;

		ZFunc = EQUAL;
		ZWriteEnable = FALSE;

		VertexShader = compile vs_3_0 Debug_Pivot_VS();
		PixelShader = compile ps_3_0 Debug_Object_PS();
	}
}

/*
	Debug frustum shaders
*/

struct APP2VS_Frustum
{
	float4 Pos : POSITION;
	float4 Color : COLOR;
};

struct VS2PS_Frustum
{
	float4 HPos : POSITION;
	float4 Pos : TEXCOORD0;
	float4 Color : TEXCOORD1;
};

VS2PS_Frustum Debug_Frustum_VS(APP2VS_Frustum Input)
{
	VS2PS_Frustum Output = (VS2PS_Frustum)0;

	Output.HPos = mul(Input.Pos, _WorldViewProj);
	Output.Pos = Output.HPos;
	#if defined(LOG_DEPTH)
		Output.Pos.w = Output.HPos.w + 1.0; // Output depth
	#endif

	Output.Color = Input.Color;

	return Output;
}

PS2FB Debug_Frustum_PS(VS2PS_Frustum Input, uniform float AlphaValue)
{
	PS2FB Output = (PS2FB)0;

	Output.Color = float4(Input.Color.rgb, Input.Color.a * AlphaValue);

	#if defined(LOG_DEPTH)
		Output.Depth = ApplyLogarithmicDepth(Input.Pos.w);
	#endif

	return Output;
}

technique wirefrustum
{
	pass Pass0
	{
		AlphaBlendEnable = TRUE;
		SrcBlend = SRCALPHA;
		DestBlend = ONE;

		ZEnable = TRUE;
		ZFunc = GREATER;
		ZWriteEnable = FALSE;

		CullMode = NONE;
		FillMode = SOLID;

		VertexShader = compile vs_3_0 Debug_Frustum_VS();
		PixelShader = compile ps_3_0 Debug_Frustum_PS(0.025);
	}

	pass Pass1
	{
		AlphaBlendEnable = FALSE;

		ZEnable = TRUE;
		ZFunc = LESSEQUAL;
		ZWriteEnable = FALSE;

		CullMode = NONE;
		FillMode = SOLID;

		VertexShader = compile vs_3_0 Debug_Frustum_VS();
		PixelShader = compile ps_3_0 Debug_Frustum_PS(1.0);
	}
}

technique solidfrustum
{
	pass Pass0
	{
		AlphaBlendEnable = TRUE;
		SrcBlend = SRCALPHA;
		DestBlend = ONE;

		ZEnable = TRUE;
		ZFunc = GREATER;
		ZWriteEnable = FALSE;

		CullMode = NONE;
		FillMode = SOLID;

		VertexShader = compile vs_3_0 Debug_Frustum_VS();
		PixelShader = compile ps_3_0 Debug_Frustum_PS(0.25);
	}

	pass Pass1
	{
		AlphaBlendEnable = FALSE;

		ZEnable = TRUE;
		ZFunc = LESSEQUAL;
		ZWriteEnable = FALSE;

		CullMode = NONE;
		FillMode = SOLID;

		VertexShader = compile vs_3_0 Debug_Frustum_VS();
		PixelShader = compile ps_3_0 Debug_Frustum_PS(1.0);
	}
}

technique projectorfrustum
{
	pass Pass0
	{
		AlphaBlendEnable = TRUE;
		SrcBlend = SRCALPHA;
		DestBlend = ONE;

		ZEnable = TRUE;
		ZFunc = LESSEQUAL;
		ZWriteEnable = FALSE;

		VertexShader = compile vs_3_0 Debug_Frustum_VS();
		PixelShader = compile ps_3_0 Debug_Frustum_PS(1.0);
	}
}
