# Base node for everything
abstract type ASTNode end

# Top-level declarations
abstract type DefNode <: ASTNode end

# Spec bodies and slots
abstract type SpecBodyNode <: ASTNode end
abstract type SpecSlotNode <: ASTNode end

# Data and Dicts
abstract type DataNode <: ASTNode end
abstract type DictTagNode <: ASTNode end

# Type expressions
abstract type TypeNode <: ASTNode end

struct Name <: ASTNode
    val::String
end

struct QName <: ASTNode
    modules::Vector{String} # For <dottedName> "::" <dottedName>
    name::String
end

struct RefNode <: ASTNode
    val::String
    display::Union{String, Nothing} # Optional [<sp> <quotedStr>]
end

struct Scalar <: ASTNode
    val::Any # Could be String, Number, etc., based on your tokenization
end

struct TypeSimple <: TypeNode
    qname::QName
end

struct TypeMaybe <: TypeNode
    base::TypeSimple
end

struct TypeAnd <: TypeNode
    types::Vector{TypeSimple}
end

struct TypeOr <: TypeNode
    types::Vector{TypeSimple}
end

# <meta> := "<" <dictTags> ">"
struct Meta <: ASTNode
    tags::Vector{DictTagNode}
end

struct DictNode <: DataNode
    datatype::Union{TypeSimple, Nothing}
    tags::Vector{DictTagNode}
end

struct DataScalar <: DataNode
    datatype::Union{TypeSimple, Nothing}
    scalar::Scalar
end

# <dictTag> variations
struct DictMarkerTag <: DictTagNode
    name::Name
end

struct DictNamedTag <: DictTagNode
    name::Name
    data::DataNode
end

struct DictUnnamedTag <: DictTagNode
    data::DataNode
end

struct DictIdTag <: DictTagNode
    ref::RefNode
    dict::DictNode
end

struct DictNamedIdTag <: DictTagNode
    name::Name
    ref::RefNode
    dict::DictNode
end

# Spec Body variations
struct SpecVal <: SpecBodyNode
    scalar::Scalar
end

struct SpecSlots <: SpecBodyNode
    slots::Vector{SpecSlotNode}
end

struct Spec <: DataNode # A Spec can also act as Data in Xeto
    type::Union{TypeNode, Nothing}
    meta::Union{Meta, Nothing}
    body::Union{SpecBodyNode, Nothing}
end

# Slot variations
struct MarkerSlot <: SpecSlotNode
    globalPrefix::Bool
    name::Name
    meta::Union{Meta, Nothing}
    leadingDoc::Vector{String}
    trailingDoc::Union{String, Nothing}
end

struct NamedSlot <: SpecSlotNode
    globalPrefix::Bool
    name::Name
    spec::Spec
    leadingDoc::Vector{String}
    trailingDoc::Union{String, Nothing}
end

struct UnnamedSlot <: SpecSlotNode
    spec::Spec
    leadingDoc::Vector{String}
    trailingDoc::Union{String, Nothing}
end

struct InlineMetaSlot <: SpecSlotNode
    tags::Vector{DictTagNode} # Contains <dictMarkerTag> variations
    leadingDoc::Vector{String}
    trailingDoc::Union{String, Nothing}
end

struct TypeDef <: DefNode
    name::Name
    spec::Spec
end

struct MixinDef <: DefNode
    type::TypeNode
    meta::Union{Meta, Nothing}
    slots::Union{SpecSlots, Nothing}
end

struct InstanceDef <: DefNode
    ref::RefNode
    dict::DictNode
end

struct LibFile <: ASTNode
    defs::Vector{DefNode}
end
