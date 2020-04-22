using DynamicalBilliards, AbstractPlotting, MakieLayout
export interactive_billiard, interactive_billiard_bmap

#TODO: Make tails transparent going towards the past (easy!)
# (add keyword fade = true)

"""
    interactive_billiard(bd::Billiard [, x, y, φ] [, ω=nothing]; kwargs...)
    interactive_billiard(bd::Billiard, ps::Vector{<:AbstractParticle}; kwargs...)

Launch an interactive application that evolves particles in a dynamical billiard `bd`, using
[DynamicalBilliards.jl](https://juliadynamics.github.io/DynamicalBilliards.jl/dev/).
You can either specify exactly the particles that will be used `ps` or provide
some initial conditions `x,y,φ,ω`, which by default are random in the billiard.

The particles are evolved in real time instead of being pre-calculated,
so the application be left to run for infinite time.

## Interaction
Push "play" to start evolving particles in the billiard, and "reset" to restore them
to their (latest) initial condition. The "particles" hides or shows the particles.
The "speed" slider controls the animation speed (in fact, it controls how often
are the plots updated).

Clicking and dragging inside the billiard plot shows a line. When the line is selected,
new particles are created that have the direction of this line, as well as its starting
position, using the function `particlebeam` from `DynamicalBilliards`.

## Further keywords
* `N = 100` : if exact particles are not given, `N` are created. Otherwise it is `length(ps)`.
* `dx = 0.01` : width of the particle beam.
* `dt = 0.001` : time resolution of the animation.
* `tail = 1000` : length of the tail of the particles (multiplies `dt`).
* colors = (:bkr, 0.75) : If a symbol/tuple (colormap name/ with alpha) each particle gets
  a color from the map. Otherwise, colors can be a vector of colors of length `N`.
* `α = 0.5` : Alpha value for the particle colors (if not given explicitly).
* `plot_particles = true` : If false, the particles are not plotted (as balls and arrows).
  This makes the application faster (you cannot show them again with the button).
"""
interactive_billiard(bd::Billiard, ω::Union{Nothing, Real} = nothing; kwargs...) =
interactive_billiard(bd::Billiard, randominside_xyφ(bd)..., ω; kwargs...)

function interactive_billiard(bd::Billiard, x::Real, y::Real, φ::Real, ω = nothing;
    kwargs...)
    N = get(kwargs, :N, 100)
    dx = get(kwargs, :dx, 0.01)
    ps = particlebeam(x, y, φ, N, dx, ω, Float32)
    interactive_billiard(bd::Billiard, ps; kwargs...)
end

function interactive_billiard(bd::Billiard, ps::Vector{<:AbstractParticle};
        dt = 0.001, tail = 1000, dx = 0.01, colors = :bkr,
        plot_particles = true, α = 0.5, N = 100, res = (800, 800),
        intervals = nothing # or arcintervals(bd)
    )

    if eltype(bd) ≠ Float32 || eltype(ps[1]) ≠ Float32
        error("Only Float32 number type is possible for the billiard applications. "*
        "Please initialize billiards and particles by explicitly passing Float32 numbers "*
        "in all numeric fields (e.g. `bd = billiard_mushroom(1f0, 0.2f0, 1f0, 0f0)`)")
    end
    N = length(ps)
    p0s = deepcopy(ps) # deep is necessary because vector of mutables
    ω0 = ismagnetic(ps[1]) ? ps[1].ω : nothing

    # Initialized inside process
    cs = colors isa Vector ? colors : colors_from_map(colors, α, N)
    scene, layout = layoutscene(resolution = res)
    ax = layout[1, 1] = LAxis(scene)
    tight_ticklabel_spacing!(ax)
    ax.autolimitaspect = 1
    allparobs = [ParObs(p, bd, tail) for p in ps]
    bdplot!(ax, bd)

    # Plot tails
    for (i, p) in enumerate(allparobs)
        lines!(ax, p.tail, color = cs[i])
        # Not working:
        # scatter!(ax, [p.pos]; color = cs[i], marker = partmarker, markersize = 6*AbstractPlotting.px)
    end

    # Plot particles
    if plot_particles
        partmarker = Circle(Point2f0(0, 0), Float32(1))
        vr = _estimate_vr(bd)
        balls = Observable([Point2f0(p.p.pos) for p in allparobs])
        vels = Observable([vr * Point2f0(p.p.vel) for p in allparobs])
        particle_plots = (
            scatter!(ax, balls; color = cs, marker = partmarker, markersize = 6AbstractPlotting.px),
            arrows!(ax, balls, vels; arrowcolor = cs, linecolor = cs,
                normalize = false, arrowsize = 0.01AbstractPlotting.px,
                linewidth  = 2,
            )
        )
    end

    # Controls:
    resetbutton = LButton(scene, label = "reset",
        buttoncolor = RGBf0(0.8, 0.8, 0.8),
        height = 40, width = 80
    )
    runbutton = LButton(scene, label = Observable("run"),
        buttoncolor = Observable(RGBf0(0.8, 0.8, 0.8)),
        buttoncolor_hover = Observable(RGBf0(0.7, 0.7, 0.9)),
        buttoncolor_active = Observable(RGBf0(0.6, 0.6, 1.0)),
        labelcolor = Observable((RGBf0(0,0,0))),
        labelcolor_active = Observable((RGBf0(1,1,1))),
        height = 40, width = 70,
    )
    nslider = LSlider(scene, range = 0:50, startvalue=0)
    controls = [resetbutton, runbutton, LText(scene, "speed:"), nslider]
    if plot_particles
        particlebutton = LButton(scene, label = "particles",
            buttoncolor = RGBf0(0.8, 0.8, 0.8),
            height = 40, width = 100
        )
        pushfirst!(controls, particlebutton)
    end

    # Functionality that CREATES the play/stop button
    # TODO: will be deleted once MakieLayout has proper togglable button
    on(runbutton.clicks) do n
        t = runbutton.label[] == "run" ? "stop" : "run"
        runbutton.label[] = t
        for (s1, s2) in ((:buttoncolor, :buttoncolor_active), (:labelcolor, :labelcolor_active))
        getproperty(runbutton, s1)[], getproperty(runbutton, s2)[] =
            getproperty(runbutton, s2)[], getproperty(runbutton, s1)[]
        end
        runbutton.labelcolor_hover[] = runbutton.labelcolor[]
    end

    # Create the "control panel"
    layout[2, 1] = grid!(hcat(
        controls...,
    ), width = Auto(false), height = Auto(true))

    # Play/stop
    on(runbutton.clicks) do nclicks
        @async while runbutton.label[] == "stop"
            for i in 1:N
                p = ps[i]
                parobs = allparobs[i]
                animstep!(parobs, bd, dt, true, intervals)
                if plot_particles
                    balls[][i] = parobs.p.pos
                    vels[][i] = vr * parobs.p.vel
                end
            end
            if plot_particles
                balls[] = balls[]
                vels[] = vels[]
            end
            for _ in 1:nslider.value[]
                for i in 1:N
                    p = ps[i]
                    parobs = allparobs[i]
                    animstep!(parobs, bd, dt, false, intervals)
                end
            end
            yield()
            isopen(scene) || break
        end
    end

    # Resetting
    on(resetbutton.clicks) do nclicks
        if runbutton.label[] == "stop"
            runbutton.clicks[] += 1 # TODO: this is a hack until full support for LToggleButton
        end
        yield()
        # update parobs
        for i in 1:N
            parobs = allparobs[i]
            rebind_partobs!(parobs, p0s[i], bd, nothing)
            if plot_particles
                balls[][i] = parobs.p.pos
                vels[][i] = vr * parobs.p.vel
            end
        end
        if plot_particles
            balls[] = balls[]
            vels[] = vels[]
        end
        yield()
    end

    # Show/hide particles
    if plot_particles
        on(particlebutton.clicks) do nclicks
            particle_plots[1].visible[] = !particle_plots[1].visible[]
            for i in 1:2
            particle_plots[2].plots[i].visible[] = !particle_plots[2].plots[i].visible[]
            end
        end
    end

    # Selecting new particles
    newparticles = select_line(ax.scene)
    on(newparticles) do val
        pos = val[1]
        dir = val[2] - val[1]
        φ = atan(dir[2], dir[1])
        p0s .= particlebeam(pos..., φ, N, dx, ω0, Float32)
        resetbutton.clicks[] += 1
    end

    display(scene)
    return scene, layout, allparobs
end

function interactive_billiard_bmap(bd::Billiard, ω=nothing; kwargs...)
    intervals = arcintervals(bd)
    scene, layout, allparobs = interactive_billiard(bd, ω;
    kwargs..., N = 1, intervals = intervals, res = (1600, 800))
    parobs = allparobs[1] # only one exists.

    # TODO: make psos a GridLayout and _then_ addit to the plot
    sublayout = GridLayout()
    bmapax = sublayout[1,1] = LAxis(scene)
    bmapax.xlabel = "ξ"
    bmapax.ylabel = "sin(φₙ)"

    layout[:, 2] = sublayout
    # scatter_points = Observable(Point2f0[])
    # on(parobs.ξsin) do v
    #     push!(scatter_points[], v)
    #     scatter_points[] = scatter_points[]
    # end
    # # TODO: Make observable of colors so that I can push random colors.
    # scatter!(bmapax, scatter_points)
    return scene, layout, allparobs
end
