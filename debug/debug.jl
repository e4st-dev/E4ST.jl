# Meant to be used for debugging during development
using E4ST
using HiGHS
using JuMP
using DataFrames
using Logging
using BasicInterpolators
import OrderedCollections: OrderedDict


config_file = joinpath(@__DIR__, "..","test","config","config_3bus.yml")
run_e4st(config_file)