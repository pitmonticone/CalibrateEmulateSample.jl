module GModel

using DocStringExtensions

# TODO: Remove build (which currently prevents segfault):
using Pkg
Pkg.build()

using Random
using Distributions
using LinearAlgebra

using DifferentialEquations
using Sundials # CVODE_BDF() solver for ODE

export run_G
export run_G_ensemble

# TODO: It would be nice to have run_G_ensemble take a pointer to the
# function G (called run_G below), which maps the parameters u to G(u),
# as an input argument. In the example below, run_G runs the model, but
# in general run_G will be supplied by the user and run the specific
# model the user wants to do UQ with.
# So, the interface would ideally be something like:
#      run_G_ensemble(params, G) where G is user-defined
"""
$(DocStringExtensions.TYPEDEF)

Structure to hold all information to run the forward model *G*.

# Fields
$(DocStringExtensions.TYPEDFIELDS)
"""
struct GSettings{FT <: AbstractFloat, KT, D}
    "A kernel tensor."
    kernel::KT
    "A model distribution."
    dist::D
    "The moments of `dist` that model should return."
    moments::Array{FT, 1}
    "Time period over which to run the model, e.g., `(0, 1)`."
    tspan::Tuple{FT, FT}
end


"""
$(DocStringExtensions.TYPEDSIGNATURES)

Run the forward model *G* for an array of parameters by iteratively
calling `run_G` for each of the *N\\_ensemble* parameter values.

- `params` - array of size (*N\\_ensemble* × *N\\_parameters*) containing the parameters for which 
  G will be run.
- `settings` - a [GSetttings](@ref) struct.

Returns `g_ens``, an array of size (*N\\_ensemble* × *N\\_data*), where g_ens[j,:] = G(params[j,:]).
"""
function run_G_ensemble(
    params::Array{FT, 2},
    settings::GSettings{FT},
    update_params,
    moment,
    get_src;
    rng_seed = 42,
) where {FT <: AbstractFloat}

    N_ens = size(params, 2) # params is N_ens x N_params
    n_moments = length(settings.moments)
    g_ens = zeros(n_moments, N_ens)

    Random.seed!(rng_seed)
    for i in 1:N_ens
        # run the model with the current parameters, i.e., map θ to G(θ)
        g_ens[:, i] = run_G(params[:, i], settings, update_params, moment, get_src)
    end

    return g_ens
end


"""
$(DocStringExtensions.TYPEDSIGNATURES)

- `u` - parameter vector of length *N\\_parameters*.
- `settings` - a [GSetttings](@ref) struct.

Returns `g_u` = *G(u)*, a vector of length *N\\_data*.
"""
function run_G(u::Array{FT, 1}, settings::GSettings{FT}, update_params, moment, get_src) where {FT <: AbstractFloat}

    # generate the initial distribution
    dist = update_params(settings.dist, u)

    # Numerical parameters
    tol = FT(1e-7)

    # Make sure moments are up to date. mom0 is the initial condition for the
    # ODE problem
    moments = settings.moments
    moments_init = fill(NaN, length(moments))
    for (i, mom) in enumerate(moments)
        moments_init[i] = moment(dist, convert(FT, mom))
    end

    # Set up ODE problem: dM/dt = f(M,p,t)
    rhs(M, p, t) = get_src(M, dist, settings.kernel)
    prob = ODEProblem(rhs, moments_init, settings.tspan)
    # Solve the ODE
    sol = solve(prob, CVODE_BDF(), alg_hints = [:stiff], reltol = tol, abstol = tol)
    # Return moments at last time step
    moments_final = vcat(sol.u'...)[end, :]

    return moments_final
end

end # module
