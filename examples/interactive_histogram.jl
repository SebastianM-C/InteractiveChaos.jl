using InteractiveChaos, Makie

ds = Systems.henonheiles()

# Grid of initial conditions at given energy:
energy(x,y,px,py) = 0.5(px^2 + py^2) + potential(x,y)
potential(x, y) = 0.5(x^2 + y^2) + (x^2*y - (y^3)/3)
function generate_ics(E, n)
    ys = range(-0.4, stop = 1.0, length = n)
    pys = range(-0.5, stop = 0.5, length = n)
    ics = Vector{Vector{Float64}}()
    for y in ys
        V = potential(0.0, y)
        V ≥ E && continue
        for py in pys
            Ky = 0.5*(py^2)
            Ky + V ≥ E && continue
            px = sqrt(2(E - V - Ky))
            ic = [0.0, y, px, py]
            push!(ics, [0.0, y, px, py])
        end
    end
    return ics
end

density = 10
tfinal = 2000.0
tgali = 1000.0
E = energy(ds.u0...)
ics = generate_ics(E, density)

tinteg = tangent_integrator(ds, 4)

regularity = Float64[]; psos = Dataset{2, Float64}[]
trs = Dataset{3, Float64}[]
@time for u in ics
    # compute gali (using advanced usage)
    reinit!(tinteg, u, orthonormal(4,4))
    push!(regularity, gali(tinteg, tgali, 1, 1e-12)[2][end]/tgali)
    push!(psos, poincaresos(ds, (1, 0.0), 2000.0; u0 = u, idxs = [2, 4]))
    tr = trajectory(ds, 100.0, u)[:, [1, 2, 4]]
    push!(trs, tr)
end

# %%

# poincare_explorer(psos, regularity; nbins = 10, α = 0.01)

poincare_explorer(trs[1:10:end], regularity[1:10:end]; nbins = 10, α = 0.1, linewidth = 2.0, transparency = true)


# %%
# using InteractiveChaos, Makie
# N = 100
# sim = [rand(50,2) for i=1:N]
# vals = rand(N)
#
# poincare_explorer(sim, vals; nbins = 10)
