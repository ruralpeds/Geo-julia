"""
Transfer Learning for Geospatial Images
"""

module TransferLearningModels

"""
    finetune_resnet50(num_classes::Int)

Fine-tune ResNet50 for spatial classification
"""
function finetune_resnet50(num_classes::Int)
    return Dict(
        "architecture" => "ResNet50",
        "pretrained" => true,
        "output_classes" => num_classes,
        "frozen_layers" => 1:30
    )
end

"""
    finetune_vgg16(num_classes::Int)

Fine-tune VGG16 for satellite image analysis
"""
function finetune_vgg16(num_classes::Int)
    return Dict(
        "architecture" => "VGG16",
        "pretrained" => true,
        "output_classes" => num_classes,
        "frozen_layers" => 1:20
    )
end

end
