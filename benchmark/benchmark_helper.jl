using Random
using DataFrames
using OrderedCollections
using CSV
using E4ST
using JuMP
using HiGHS

function make_random_inputs(;n_bus = 100, n_gen = 100, n_branch=100, n_af=100, n_hours=100, n_load = 200, n_load_shape=100, n_load_match = 100, n_load_add = 100, af_file=true, load_shape_file=true, load_match_file=true, load_add_file=true)
    Random.seed!(1)


    ## Make Bus Table
    bus = DataFrame(
        ref_bus = fill(false, n_bus),
        plnom = rand(n_bus),
        country = rand(countries(), n_bus)
    )
    ref_bus_idx = rand(1:n_bus)
    bus.ref_bus[ref_bus_idx] = true

    gen = DataFrame(
        bus_idx = rand(1:n_bus, n_gen),
        status = trues(n_gen),
        build_status = rand(build_status_opts(), n_gen),
        build_type = rand(build_type_opts(), n_gen),
        build_id = fill("", n_gen),
        genfuel = rand(genfuels(), n_gen),
        pcap_min = zeros(n_gen),
        pcap0 = ones(n_gen),
        pcap_max = ones(n_gen),
        vom = rand(n_gen),
        fuel_price = rand(n_gen),
        heat_rate = 10*rand(n_gen),
        fom = rand(n_gen),
        capex = rand(n_gen),
        year_on = year2str.(rand(2000:2023, n_gen)),
        year_off = fill("y9999", n_gen),
        year_shutdown = fill("y9999", n_gen),
        econ_life = fill(30, n_gen),
        hr = rand(n_gen),
        chp_co2_multi = ones(n_gen),
    )
    gen.pcap_inv = copy(gen.pcap0)
    gt = gentypes()
    gen.gentype = map(gen.genfuel) do gf
        rand(gt[gf])
    end

    branch = DataFrame(
        f_bus_idx = rand(1:n_bus, n_branch),
        t_bus_idx = rand(1:n_bus, n_branch),
        status = trues(n_branch),
        x = fill(0.01, n_branch),
        pflow_max = rand(n_branch)
    )

    

    h = rand(n_hours)
    h = h * 8760/sum(h)
    time = DataFrame(
        hours=h
    )

    isdir(joinpath(@__DIR__,"data")) || mkdir(joinpath(@__DIR__,"data"))
    CSV.write(joinpath(@__DIR__, "data/bus.csv"), bus)
    CSV.write(joinpath(@__DIR__, "data/gen.csv"), gen)
    CSV.write(joinpath(@__DIR__, "data/branch.csv"), branch)
    CSV.write(joinpath(@__DIR__, "data/time.csv"), time)
    config = OrderedDict(
        :base_out_path=>abspath(@__DIR__,"out"),
        :gen_file=>abspath(@__DIR__,"data/gen.csv"),
        :bus_file=>abspath(@__DIR__,"data/bus.csv"),
        :branch_file=>abspath(@__DIR__, "data/branch.csv"),
        :hours_file=>abspath(@__DIR__, "data/time.csv"),
        :summary_table_file=>abspath(@__DIR__, "../test/data/3bus/summary_table.csv"),
        :gentype_genfuel_file=>abspath(@__DIR__, "data/gentype_genfuel.csv"),
        :year_gen_data => "y2020",
        :years=>years(),
        :save_data=>false,
        :save_model_presolve=>false,
        :optimizer=>OrderedDict(
            :type=>"HiGHS",
        ),
        :mods=>Modification[]
    )
    n_years = length(years())

    load = rand_load(;n_bus, n_load)
    CSV.write(joinpath(@__DIR__, "data/load.csv"), load)
    config[:nominal_load_file] = abspath(@__DIR__, "data/load.csv")

    if af_file
        af = rand_af(;n_hours, n_af)
        CSV.write(joinpath(@__DIR__, "data/af.csv"), af)
        config[:af_file] = abspath(@__DIR__, "data/af.csv")
    end

    if load_shape_file
        load_shape = rand_load_shape(;n_hours, n_load_shape)
        CSV.write(joinpath(@__DIR__, "data/load_shape.csv"), load_shape)
        config[:load_shape_file] = abspath(@__DIR__, "data/load_shape.csv")
    end

    if load_match_file
        load_match = rand_load_match(;n_years, n_load_match)
        CSV.write(joinpath(@__DIR__, "data/load_match.csv"), load_match)
        config[:load_match_file] = abspath(@__DIR__, "data/load_match.csv")
    end



    if load_add_file
        load_add = rand_load_add(;n_hours, n_load_add)
        CSV.write(joinpath(@__DIR__, "data/load_add.csv"), load_add)
        config[:load_add_file] = abspath(@__DIR__, "data/load_add.csv")
    end
    
    check_config!(config)

    return config
end

function years()
    ["y$y" for y in 2030:5:2050]
end
function year_strs()
    year_strs = vcat(years(), "")
end

function load_types()
    ("ev", "residential", "commercial", "industrial", "transportation")
end
function countries()
    ("narnia", "calormen", "archenland", "telmar")
end


function rand_load(;n_bus, n_load, kwargs...)
    DataFrame(
        "bus_idx" => rand(1:n_bus, n_load),
        "plnom0" => rand(n_load),
        "load_type" => rand(load_types())
    )
end

function genfuels()
    ("biomass","nuclear","ng","coal","solar","hydro", "wind", "geothermal")
end
gentypes() = OrderedDict(
    "biomass"=>["biomass","biomass_new"],
    "nuclear"=>["nuclear","nuclear_new"],
    "ng"=>["ng","ng_cc","ng_ccccs"],
    "coal"=>["coal","coal_ccs"],
    "solar"=>["solar","solar_new"],
    "hydro"=>["hydro","hydro_new"],
    "wind"=>["wind","wind_new"],
    "geothermal"=>["hydrothermal","deepgeo_new"],
)

function build_status_opts()
    ("built", "new", "unbuilt")
end

function build_type_opts()
    ("exog", "endog")
end

function rand_af(;n_hours, n_af)
    af = DataFrame(
        "area" => String[],
        "subarea" => String[],
        "genfuel" => String[],
        "gentype" => String[],
        "year"=>String[],
        "joint" => Int64[],
        "status" => Bool[],
        ("h$n"=>Float64[] for n in 1:n_hours)...
    )
    joint = 1
    gt = gentypes()
    yrs = year_strs()
    while nrow(af) < n_af
        for country in countries()
            joint += 1
            for genfuel in genfuels(), gentype in gt[genfuel]
                year = rand(yrs)
                push!(af, ("country", country, genfuel, gentype, year, joint, true, rand(n_hours)...))
                if nrow(af) == n_af
                    break
                end
            end
            if nrow(af) == n_af
                break
            end
        end
    end
    return af
end

function rand_load_shape(;n_hours, n_load_shape)
    load_shape = DataFrame(
        "area" => String[],
        "subarea" => String[],
        "load_type" => String[],
        "year"=>String[],
        "joint" => Int64[],
        "status" => Bool[],
        ("h$n"=>Float64[] for n in 1:n_hours)...
    )
    joint = 1
    gf = genfuels()
    gt = gentypes()
    yrs = year_strs()
    lts = load_types()
    while nrow(load_shape) < n_load_shape
        for country in countries()
            joint += 1
            for lt in lts
                year = rand(yrs)
                push!(load_shape, ("country", country, lt, year, joint, true, rand(n_hours)...))
                if nrow(load_shape) == n_load_shape
                    break
                end
            end
            if nrow(load_shape) == n_load_shape
                break
            end
        end
    end
    return load_shape
end

function rand_load_match(;n_years, n_load_match)
    load_match = DataFrame(
        "area" => String[],
        "subarea" => String[],
        "load_type" => String[],
        "joint" => Int64[],
        "status" => Bool[],
        [ys=>Float64[] for ys in years()]...
    )
    joint = 1
    gf = genfuels()
    gt = gentypes()
    lts = load_types()
    while nrow(load_match) < n_load_match
        for country in countries()
            joint += 1
            for lt in lts
                push!(load_match, ("country", country, lt, joint, true, rand(n_years)...))
                if nrow(load_match) == n_load_match
                    break
                end
            end
            if nrow(load_match) == n_load_match
                break
            end
        end
    end
    return load_match
end

function rand_load_add(;n_hours, n_load_add)
    load_add = DataFrame(
        "area" => String[],
        "subarea" => String[],
        "load_type" => String[],
        "year"=>String[],
        "joint" => Int64[],
        "status" => Bool[],
        ("h$n"=>Float64[] for n in 1:n_hours)...
    )
    joint = 1
    gf = genfuels()
    gt = gentypes()
    yrs = year_strs()
    lts = load_types()
    while nrow(load_add) < n_load_add
        for country in countries()
            joint += 1
            for lt in lts
                year = rand(yrs)
                push!(load_add, ("country", country, lt, year, joint, true, rand(n_hours)...))
                if nrow(load_add) == n_load_add
                    break
                end
            end
            if nrow(load_add) == n_load_add
                break
            end
        end
    end
    return load_add
end