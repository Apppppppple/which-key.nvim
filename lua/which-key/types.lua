---@class Keymap
---@field rhs string
---@field lhs string
---@field buffer number
---@field expr number
---@field lnum number
---@field mode string
---@field noremap number
---@field nowait number
---@field script number
---@field sid number
---@field silent number
---@field id string terminal codes for lhs
local Keymap

---@class KeyCodes
---@field keys string
---@field term string[]
---@field nvim string[]
local KeyCodes

---@class MappingOptions
---@field noremap boolean
---@field silent boolean
---@field nowait boolean
local MappingOptions

---@class Mapping
---@field buf number
---@field group boolean
---@field label string
---@field prefix string
---@field cmd string
---@field opts MappingOptions
---@field keys KeyCodes
---@field plugin string
local Mapping

---@class MappingTree
---@field mode string
---@field buf number
---@field tree Tree
local MappingTree

---@class VisualMapping : Mapping
---@field key string
---@field highlights table
---@field value string
local VisualMapping

---@class PluginItem
---@field key string
---@field label string
---@field value string
---@field cmd string
---@field highlights table
local PluginItem

---@class Plugin
---@field name string
---@field actions string[] | string[][]
---@field run fun(trigger:string, mode:string, buf:number):PluginItem[]
---@field setup fun()
local Plugin
