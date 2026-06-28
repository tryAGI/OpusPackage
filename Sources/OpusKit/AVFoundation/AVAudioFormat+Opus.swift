#if canImport(AVFoundation)
    import AVFoundation
    import OpusTypes

    public extension Opus.PCMFormat {
        @inlinable var avCommonFormat: AVAudioCommonFormat {
            switch self {
            case .int16: .pcmFormatInt16
            case .float32: .pcmFormatFloat32
            }
        }
    }

    public extension AVAudioFormat {
        convenience init?(
            opusPCMFormat: Opus.PCMFormat,
            sampleRate: Opus.SampleRate,
            channels: Opus.Channels
        ) {
            self.init(
                commonFormat: opusPCMFormat.avCommonFormat,
                sampleRate: Double(sampleRate.rawValue),
                channels: AVAudioChannelCount(channels.rawValue),
                interleaved: channels != .mono
            )
            guard isValidOpusPCMFormat else { return nil }
        }

        var isValidOpusPCMFormat: Bool {
            // Legal Opus rates only
            guard Opus.SampleRate(hz: sampleRate) != nil else { return false }

            // Only mono/stereo for classic encoder
            guard Opus.Channels(avCount: channelCount) != nil else { return false }

            // Stereo must be interleaved
            if channelCount == 2 && !isInterleaved { return false }

            // Accept the two common PCM formats outright, otherwise validate ASBD
            if commonFormat == .pcmFormatInt16 || commonFormat == .pcmFormatFloat32 { return true }

            let desc = streamDescription.pointee
            if desc.mFormatID != kAudioFormatLinearPCM {
                return false
            }
            if desc.mFormatFlags & kLinearPCMFormatFlagIsSignedInteger != 0, desc.mBitsPerChannel != 16 {
                return false
            }
            if desc.mFormatFlags & kLinearPCMFormatFlagIsFloat != 0, desc.mBitsPerChannel != 32 {
                return false
            }

            return true
        }
    }
#endif
