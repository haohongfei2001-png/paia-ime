import Foundation
import FoundationModels
if #available(macOS 26.0, *) {
    print("on_device_model_availability=\(SystemLanguageModel.default.availability)")
    print("generation_calls=0; cloud_calls=0")
}
