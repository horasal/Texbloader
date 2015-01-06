use zlib
import structs/ArrayList
import io/BinarySequence
import io/[FileReader, FileWriter, BufferReader]

Color: cover{
	R, G, B, A: UInt8
}

Bitmap: class{
	pixels: ArrayList<Color> = ArrayList<Color> new()

	init: func

	addPixel: func ~color (c: Color){ pixels add(c) }
	addPixel: func ~rgb (r,g,b: Int8){ pixels add((r,g,b,255) as Color) }
	addPixel: func ~rgba (r,g,b,a: Int8){ pixels add((r,g,b,a) as Color) }

    save: func(buffer: BinarySequenceWriter, height, width: Int){
        for(i in 0..height){
            for(j in 0..width){
                buffer u8(pixels[(height-i-1)*width+j] B)
                buffer u8(pixels[(height-i-1)*width+j] G)
                buffer u8(pixels[(height-i-1)*width+j] R)
                buffer u8(pixels[(height-i-1)*width+j] A)
            }
        }
	}

    size: func -> UInt32{
        pixels size * 4 * UInt8 size
    }
}

Vertex: cover{
	x, y, z: Float
}

UV: cover{
    u, v: Float
}

Attribute: cover{
    id, type, value: UInt32
    str: String

    is3dModel: Bool = false 
    loadUVIndex: Bool = false

    init: func(buffer: BinarySequenceReader){
        id = buffer u8()
        type = buffer u8()
        match(id){
            case 11 => // 3dmodel
                is3dModel = true
            case =>
        }
        match(type){
            case 0 =>
                value = buffer u32()
                if(is3dModel){
                    loadUVIndex = value & 0x80000000 ? true : false
                } 
            case 1 => 
                value = buffer u32()
                if(is3dModel){
                    loadUVIndex = value & 0x80000000 ? true : false
                } 
            case 2 => // string
                str = buffer pascalString(2)
            case => Exception new("Invalid Image Attribute Type") throw()
        }
    }
}

Tile: class{
	verticesList: ArrayList<Vertex> = ArrayList<Vertex> new()
    uvList: ArrayList<UV> = ArrayList<UV> new()
	indexesList: ArrayList<Int> = ArrayList<Int> new()

    boundWidth, boundHeight: Float

    vertices, indexes: Int
    right, bottom: Int
    centerX, centerY: Int

    init: func(buffer: BinarySequenceReader, is3dModel, loadUVIndex, compactUV: Bool){
        if(is3dModel){
            vertices = buffer u16()
            indexes = buffer u16()
        } else {
            vertices = buffer u8()
            indexes = buffer u8()
        }

        right = buffer u16()
        bottom = buffer u16()
        centerX = buffer u16()
        centerY = buffer u16()
       
        max := const static 65536.0f
        maxX := const static 9999.0f
        maxY := const static 9999.0f
        minX := const static -9999.0f
        minY := const static -9999.0f

        for(n in 0.. vertices){
            x := buffer u32() as Float / max - centerX
            y := buffer u32() as Float / max - centerY
            z := 0.0f
            if(is3dModel){
                z = buffer u32() as Float / max
            } else {
                if(x < minX) minX = x
                if(x > maxX) maxX = x
                if(y < minY) minY = y
                if(y > maxY) maxY = y
            }
            verticesList add((x, y, z) as Vertex)
            uvmax := const static 32768.0f
            if(loadUVIndex){
                if(compactUV){
                    uvList add((buffer u16() as Float / uvmax, buffer u16() as Float / uvmax) as UV)
                } else {
                    uvList add((buffer u32() as Float / uvmax, buffer u32() as Float / uvmax) as UV)
                }
            }
        }

        if(loadUVIndex){
            for(i in 0..indexes){
                indexesList add(buffer u8())
            }
        }

        boundWidth = maxX - minX
        boundHeight = maxY - minY

    }
}

Timg: class{
	path: String
	size: Int
    is3dModel := false
    loadUVIndex := true
    compactUV := false
    attributesList: ArrayList<Attribute> = ArrayList<Attribute> new()
    tilesList: ArrayList<Tile> = ArrayList<Tile> new()


	toString: func -> String{
        "Timg: %s, size: %d\n" format(path, size) + \
        "tiles: %d, attributes: %d\n" format(tilesList size, attributesList size) + \
        "is3dModel: %s, loadUVIndex: %s, compactUV: %s" format(is3dModel toString(), loadUVIndex toString(), compactUV toString())
    }

	init: func(buffer: BinarySequenceReader){
		if(buffer u32() != 0x54494d47) Exception new("Incorrect Magic of Timg") throw()
		size = buffer u16()
        if(size == 0xFFFF) size = buffer u32()
		path = buffer pascalString(2)
        subTiles := buffer u16()
        if(subTiles == 0xFFFE){ compactUV = true }
        if(subTiles = 0xFFFF){
            attribs := buffer u16()
            for(i in 0..attribs){
                att := Attribute new(buffer)
                is3dModel |= att is3dModel
                loadUVIndex |= att loadUVIndex
                attributesList add(att)
            }
            subTiles = buffer u16()
        }
        for(i in 0..subTiles){
            tilesList add(Tile new(buffer, is3dModel, loadUVIndex, compactUV))
        }
	}
}


PixelFormat: enum{
    RGB565,
    RGB5551,
    RGB4444,
    RGB8888
}


Texb: class{
	path: String
	size: Int
	width: Int
	height: Int
	type: Int
	isCompressed: Bool
	isMipmap: Bool
	isDoubleBuffered: Bool
	pixelFormat: Int
    pf: PixelFormat

    channelCount: Int = 0

	vertices: Int
	indexes: Int
	images: Int

	timgs: ArrayList<Timg> = ArrayList<Timg> new()

	bitmap: Bitmap = Bitmap new()

	save: func(buffer: BinarySequenceWriter){
        // bmp file header
		buffer bytes("BM")
        buffer u32(0x0e+0x28+bitmap size())
		buffer u16(0)
        buffer u16(0)
		buffer u32(0x36)

        // DIB header
		buffer u32(0x28)
		buffer u32(width)
		buffer u32(height)
		buffer u16(0x01)
		buffer u16(0x20)
		buffer u32(0)
		buffer u32(bitmap size())
		buffer u32(0)
		buffer u32(0)
		buffer u32(0)
		buffer u32(0)
		bitmap save(buffer, height, width)
	}

	toString: func -> String{
		"Texb: %s, size: %d\n" format(path, size) + \
		"w: %d, h: %d, type: %d\n" format(width, height, type) + \
		"compressed: %s, mipmap: %s, doublefbuf: %s\n" format(isCompressed toString(), isMipmap toString(), isDoubleBuffered toString()) + \
		"pixelformat: %d\n" format(pixelFormat) + \
		"v: %d, i: %d, images: %d" format(vertices, indexes, images)
	}

	init: func(buffer: BinarySequenceReader){
		if(buffer u32() != 0x54455842) Exception new("Incorrect Magic for Texb") throw()
		size = buffer u32()
		path = buffer pascalString(2)
		width = buffer u16()
		height = buffer u16()
		tp := buffer u16()
		type = tp & 0x07
		isCompressed = ((tp >> 3) & 0x01) as Bool
		isMipmap = ((tp >> 4) & 0x01) as Bool
		isDoubleBuffered = ((tp >> 5) & 0x01) as Bool
		pixelFormat = (tp >> 6) & 0x03

		vertices = buffer u16()
        if(vertices == 0xFFFF){ vertices = buffer u32() }
		indexes = buffer u16()
        if(indexes == 0xFFFF){ indexes = buffer u32() }
		images = buffer u16()

        uvOffset := 0
        if(tp & 0x8000){
            uvOffset = buffer u32()
        } else {
            uvOffset = vertices * 2
            vertices *= 4
        }

		for(i in 0..images){ timgs add(Timg new(buffer)) }

        channelCount = match(type){
            case 0 => 1
            case 1 => 0
            case 2 => 2
            case 3 => 3
            case => 4
        }

        // all remaining data is bitmap data
        hasClick := 0
        bytePerPixel := 0
        match(pixelFormat){
            case 0 =>
                hasClick = 0
                bytePerPixel = 2
                pf = PixelFormat RGB565
            case 1 => 
                hasClick = 1
                bytePerPixel = 2
                pf = PixelFormat RGB5551
            case 2 => 
                hasClick = 1
                bytePerPixel = 2
                pf = PixelFormat RGB4444
            case =>
                bytePerPixel = channelCount ? channelCount : 1
                hasClick = 1
                pf = PixelFormat RGB8888
        }

        bmpReader := buffer 

        if(isCompressed){
            // compress type
            match(compresstype := buffer u32()){
                case 0 => //zlib
                    clength : ULong = size + 8 - buffer bytesRead
                    cbuffer: UChar* = buffer bytes(clength)
                    rlength : ULong = width * height * bytePerPixel
                    destbuffer : UChar* = gc_malloc(rlength * UChar size)
                    errno: Int
                    if(errno = Zlib decompress(destbuffer, rlength&, cbuffer, clength)){
                        Exception new("decompress error, error no %d" format(errno)) throw()
                    }
                    bmpReader = BinarySequenceReader new(BufferReader new(Buffer new(destbuffer, rlength)))
                case 0x8D64 => // Adaptive Scalable Texture Compression
                    bytePerPixel = 4
                    pixelFormat = 0x1401 // GL_UNSIGNED_BYTE, but we don't care because it won't be used
                    Exception new("need to be implemented") throw()

                case 0x8363 => pf = PixelFormat RGB565
                case 0x8034 => pf = PixelFormat RGB5551
                case 0x8033 => pf = PixelFormat RGB4444
                case 0x1401 => pf = PixelFormat RGB8888
                case =>
                    Exception new("Unsupported Compress Format: 0x%x" format(compresstype)) throw()
            }
        }

        // Playground also support "lowRes" translation for small devices.
        // Clicking Alpha will also be computed here
        // currently we will ignore them

        match(pf){
            case PixelFormat RGB8888 => 
                loadRGB8888(bmpReader)
            case PixelFormat RGB565 => 
                loadRGB565(bmpReader)
            case PixelFormat RGB4444 => 
                loadRGB4444(bmpReader)
            case PixelFormat RGB5551 => 
                loadRGB5551(bmpReader)
            case =>
                Exception new("Unsupported BMP Pixel Format") throw()

        }
	}

	loadRGB8888: func(buffer: BinarySequenceReader){
		for(i in 0..width*height){
			bitmap addPixel(buffer u8(), buffer u8(), buffer u8(), buffer u8())	
		}
	}

    loadRGB4444: func(buffer: BinarySequenceReader){
        for(i in 0..width*height){
            b1 : UInt16 = buffer u16()
            tmp : UInt8 = (b1 & 0xF000) >> 8
            r := tmp | (tmp >> 4)
            tmp = (b1 & 0x0F00) >> 4
            g := tmp | (tmp >> 4)
            tmp = (b1 & 0x00F0)
            b := tmp | (tmp >> 4)
            tmp = (b1 & 0x000F)
            a := tmp | (tmp << 4)
            bitmap addPixel(r, g, b, a)
        }
    }

    loadRGB5551: func(buffer: BinarySequenceReader){
        for(i in 0..width*height){
            b1 : UInt16 = buffer u16()
            tmp : UInt8 = (b1 & 0xF800) >> 8
            r := tmp | (tmp >> 5)
            tmp = (b1 & 0x07C0) >> 3
            g := tmp | (tmp >> 5)
            tmp = (b1 & 0x003E) << 2
            b := tmp | (tmp >> 5)
            a := ((tmp & 0x01) as UInt8 << 7) >> 7
            bitmap addPixel(r, g, b, a) 
        }
    }

    loadRGB565: func(buffer: BinarySequenceReader){
        for(i in 0..width*height){
            b1 : UInt16 = buffer u16()
            tmp : UInt8 = (b1 & 0xF800) >> 8
            r := tmp | (tmp >> 5)
            tmp = (b1 & 0x07E0) >> 3
            g := tmp | (tmp >> 6)
            tmp = (b1 & 0x001F) << 3
            b := tmp | (tmp >> 5)
            bitmap addPixel(r, g, b, 255) 
        }
    }
}
