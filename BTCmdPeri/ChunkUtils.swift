//
//  ChunkUtils.swift
//  BTCmdPeri
//
//  Created by Jay Tucker on 4/9/15.
//  Copyright (c) 2015 Imprivata. All rights reserved.
//

enum ChunkFlag: UInt8, Printable {
    case First  = 1
    case Middle = 0
    case Last   = 2
    case Only   = 3
    
    var description: String {
        switch(self) {
        case .First:  return "F"
        case .Middle: return "M"
        case .Last:   return "L"
        case .Only:   return "O"
        }
    }
    
}

class Chunker {
    class func makeChunks(bytes: [UInt8], var chunkSize: Int) -> Array< Array<UInt8> > {
        if chunkSize < 1 || chunkSize > 0x3fff {
            chunkSize = 0x3fff
        }
        var chunks = Array<Array<UInt8>>()
        let totalSize = bytes.count
        var begIdx = 0
        while (begIdx < totalSize) {
            let nextBegIdx = begIdx + chunkSize
            let endIdx = min(nextBegIdx, totalSize)
            var flag: ChunkFlag
            if chunks.isEmpty {
                if nextBegIdx < totalSize {
                    flag = ChunkFlag.First
                } else {
                    flag = ChunkFlag.Only
                }
            } else {
                if nextBegIdx < totalSize {
                    flag = ChunkFlag.Middle
                } else {
                    flag = ChunkFlag.Last
                }
            }
            let chunkDataBytes = Array<UInt8>(bytes[begIdx..<endIdx])
            var header: [UInt8] = [0,0]
            let length = chunkDataBytes.count
            header[0] = (flag.rawValue << 6) + UInt8(length >> 8)
            header[1] = UInt8(length & 0xff)
            chunks.append(header + chunkDataBytes)
            begIdx = nextBegIdx
        }
        return chunks
    }
}

class Dechunker {
    private var buffer: [UInt8]
    
    init() {
        buffer = [UInt8]()
    }
    
    func addChunk(var bytes: [UInt8]) -> (isSuccess: Bool, finalResult: [UInt8]?) {
        log("dechunker attempting to add chunk of 2+\(bytes.count - 2)=\(bytes.count) bytes")
        if bytes.count < 2 {
            log("dechunker failed: too few bytes")
            return (false, nil)
        }
        let flagRawValue = bytes[0] >> 6
        let flag = ChunkFlag(rawValue: flagRawValue)!
        let length = Int((bytes[0] & 0x3f) + bytes[1])
        if length == (bytes.count - 2) {
            let data = Array<UInt8>(bytes[2..<bytes.count])
            switch flag {
            case .First, .Only:
                buffer = data
                log("dechunker created buffer with \(data.count) bytes (\(flag.description))")
            case .Middle, .Last:
                buffer += data
                log("dechunker added \(data.count) bytes (\(flag.description))")
            }
            switch flag {
            case .Last, .Only:
                log("dechunker complete")
                return (true, buffer)
            case .First, .Middle:
                return (true, nil)
            }
        } else {
            log("dechunker failed: bad length")
        }
        return (false, nil)
    }
    
}

func dumpChunks(chunks: Array< Array<UInt8> >) {
    for chunk in chunks {
        let flagRawValue = chunk[0] >> 6
        let flag = ChunkFlag(rawValue: flagRawValue)!
        let length = (chunk[0] & 0x3f) + chunk[1]
        log("(\(flag.description),\(length)): \(chunk)")
    }
}
