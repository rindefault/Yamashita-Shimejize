#ifndef MATERIAL_IDS_GLSL
#define MATERIAL_IDS_GLSL

bool isFoliageWindBlock(float blockId) {
	return blockId == 10059.0 || blockId == 10060.0 || blockId == 10061.0
		|| blockId == 10032.0 || blockId == 10175.0 || blockId == 10176.0;
}

bool isWaterBlock(float blockId) {
	return blockId == 10008.0;
}

bool isNetherPortalBlock(float blockId) {
	return blockId == 10092.0;
}

#endif
