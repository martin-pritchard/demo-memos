import Core
import Foundation

/// A raised-when-a-file-can't-be-read error. Typed so tests can distinguish a
/// truncated file from an unsupported one from a non-WAV entirely.
enum WAVError: Error, Equatable {
  case notRIFF
  case notWAVE
  case truncated
  case unsupportedFormat
  case missingFormat
  case missingData
}

/// A pure-Swift 24-bit PCM WAV codec — no `AVFoundation`, so the harness runs
/// under `swift test` with no simulator. It reads only what this project's
/// fixtures and a real iPhone export need: 24-bit linear PCM, `WAVE_FORMAT_PCM`
/// or `WAVE_FORMAT_EXTENSIBLE`, skipping any chunk it doesn't recognise.
enum WAVFile {
  /// Full scale is ±(2²³ − 1), applied symmetrically on the way in and out, so a
  /// generated 1.0 encodes to the top code and reads back as exactly 1.0
  /// (`x / x == 1` in IEEE 754). A ±2²³ mapping would leave +1.0 unrepresentable
  /// and the impulse fixture a hair below full scale.
  private static let fullScale = Float(0x7F_FFFF)  // 2²³ − 1 = 8_388_607

  // MARK: - Read

  static func read(_ data: Data) throws -> SampleBuffer {
    let bytes = [UInt8](data)
    guard bytes.count >= 12 else { throw WAVError.truncated }
    guard readTag(bytes, 0) == "RIFF" else { throw WAVError.notRIFF }
    guard readTag(bytes, 8) == "WAVE" else { throw WAVError.notWAVE }

    var format: Format?
    var samples: [Float]?

    var offset = 12
    while offset + 8 <= bytes.count {
      let id = readTag(bytes, offset)
      let size = Int(readU32(bytes, offset + 4))
      let body = offset + 8
      guard body + size <= bytes.count else { throw WAVError.truncated }

      switch id {
      case "fmt ":
        format = try readFormat(bytes, at: body, size: size)
      case "data":
        guard let format else { throw WAVError.missingFormat }
        samples = decode(bytes, at: body, size: size, format: format)
      default:
        break  // LIST, fact, FLLR, anything else — skip it.
      }

      // Chunks are word-aligned: an odd size carries a pad byte not in `size`.
      offset = body + size + (size & 1)
    }

    guard let format else { throw WAVError.missingFormat }
    guard let samples else { throw WAVError.missingData }
    return SampleBuffer(
      sampleRate: format.sampleRate,
      channelCount: format.channelCount,
      samples: samples
    )
  }

  private struct Format {
    var channelCount: Int
    var sampleRate: Double
    var bitsPerSample: Int
  }

  private static func readFormat(_ bytes: [UInt8], at body: Int, size: Int) throws -> Format {
    guard size >= 16 else { throw WAVError.truncated }
    let tag = readU16(bytes, body)
    let channelCount = Int(readU16(bytes, body + 2))
    let sampleRate = Double(readU32(bytes, body + 4))
    let bitsPerSample = Int(readU16(bytes, body + 14))

    var isPCM = tag == 0x0001
    if tag == 0xFFFE {  // WAVE_FORMAT_EXTENSIBLE — the real tag is in the sub-format GUID.
      guard size >= 40 else { throw WAVError.truncated }
      isPCM = readU16(bytes, body + 24) == 0x0001
    }
    guard isPCM else { throw WAVError.unsupportedFormat }
    guard bitsPerSample == 24 else { throw WAVError.unsupportedFormat }
    return Format(channelCount: channelCount, sampleRate: sampleRate, bitsPerSample: bitsPerSample)
  }

  private static func decode(_ bytes: [UInt8], at body: Int, size: Int, format: Format) -> [Float] {
    let bytesPerSample = 3
    let count = size / bytesPerSample
    var samples = [Float]()
    samples.reserveCapacity(count)
    var p = body
    for _ in 0..<count {
      let raw = UInt32(bytes[p]) | UInt32(bytes[p + 1]) << 8 | UInt32(bytes[p + 2]) << 16
      // Sign-extend the 24-bit code: park it in the top of an Int32, then shift
      // back down arithmetically.
      let value = Int32(bitPattern: raw << 8) >> 8
      samples.append(Float(value) / fullScale)
      p += bytesPerSample
    }
    return samples
  }

  // MARK: - Write

  static func encode(_ buffer: SampleBuffer) throws -> Data {
    let channelCount = buffer.channelCount
    let bytesPerSample = 3
    let blockAlign = channelCount * bytesPerSample
    let byteRate = Int(buffer.sampleRate) * blockAlign
    let dataSize = buffer.samples.count * bytesPerSample

    var data = Data()
    data.append(ascii: "RIFF")
    data.append(u32: UInt32(36 + dataSize))
    data.append(ascii: "WAVE")

    data.append(ascii: "fmt ")
    data.append(u32: 16)
    data.append(u16: 0x0001)  // WAVE_FORMAT_PCM
    data.append(u16: UInt16(channelCount))
    data.append(u32: UInt32(buffer.sampleRate))
    data.append(u32: UInt32(byteRate))
    data.append(u16: UInt16(blockAlign))
    data.append(u16: 24)

    data.append(ascii: "data")
    data.append(u32: UInt32(dataSize))
    for sample in buffer.samples {
      let clamped = min(max(sample, -1.0), 1.0)
      let code = Int32((clamped * fullScale).rounded())
      let unsigned = UInt32(bitPattern: code)
      data.append(UInt8(unsigned & 0xFF))
      data.append(UInt8((unsigned >> 8) & 0xFF))
      data.append(UInt8((unsigned >> 16) & 0xFF))
    }
    return data
  }

  // MARK: - Little-endian reads

  private static func readTag(_ bytes: [UInt8], _ offset: Int) -> String {
    String(bytes: bytes[offset..<offset + 4], encoding: .ascii) ?? ""
  }

  private static func readU16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
    UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
  }

  private static func readU32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
    UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
      | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
  }
}

private extension Data {
  mutating func append(ascii: String) { append(contentsOf: Array(ascii.utf8)) }
  mutating func append(u16 value: UInt16) {
    append(UInt8(value & 0xFF))
    append(UInt8((value >> 8) & 0xFF))
  }
  mutating func append(u32 value: UInt32) {
    append(UInt8(value & 0xFF))
    append(UInt8((value >> 8) & 0xFF))
    append(UInt8((value >> 16) & 0xFF))
    append(UInt8((value >> 24) & 0xFF))
  }
}
