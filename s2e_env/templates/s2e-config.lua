--[[
This is the main S2E configuration file
=======================================

This file was automatically generated by s2e-env at {{ creation_time }}.
Changes can be made by the user where appropriate.
]]--

-------------------------------------------------------------------------------
-- This section configures the S2E engine.
s2e = {
    logging = {
        -- Possible values include "info", "warn", "debug", "none".
        -- See Logging.h in libs2ecore.
        console = "debug",
        logLevel = "debug",
    },

    -- All the cl::opt options defined in the engine can be tweaked here.
    -- This can be left empty most of the time.
    -- Most of the options can be found in S2EExecutor.cpp and Executor.cpp.
    kleeArgs = {
    },
}

-- Declare empty plugin settings. They will be populated in the rest of
-- the configuration file.
plugins = {}
pluginsConfig = {}

-- Include various convenient functions
dofile('library.lua')

-------------------------------------------------------------------------------
-- This plugin contains the core custom instructions.
-- Some of these include s2e_make_symbolic, s2e_kill_state, etc.
-- You always want to have this plugin included.

add_plugin("BaseInstructions")

-------------------------------------------------------------------------------
-- This plugin implements "shared folders" between the host and the guest.
-- Use it in conjunction with s2eget and s2eput guest tools in order to
-- transfer files between the guest and the host.

add_plugin("HostFiles")
pluginsConfig.HostFiles = {
    baseDirs = {
        "{{ project_dir }}",
        {% if use_seeds == true %}
        "{{ seeds_dir }}",
        {% endif %}
    },
    allowWrite = true,
}

-------------------------------------------------------------------------------
-- This plugin provides support for virtual machine introspection and binary
-- formats parsing. S2E plugins can use it when they need to extract
-- information from binary files that are either loaded in virtual memory
-- or stored on the host's file system.

add_plugin("Vmi")
pluginsConfig.Vmi = {
    baseDirs = {
        "{{ project_dir }}", "{{ project_dir }}/guest-tools",
        {% if has_guestfs %}
        "{{ guestfs_dir }}"
        {% endif %}
    },
}

-------------------------------------------------------------------------------
-- This plugin provides various utilities to read from process memory.
-- In case it is not possible to read from guest memory, the plugin tries
-- to read static data from binary files stored in guestfs.
add_plugin("MemUtils")

-------------------------------------------------------------------------------
-- This plugin collects various execution statistics and sends them to a QMP
-- server that listens on an address:port configured by the S2E_QMP_SERVER
-- environment variable.
--
-- The "s2e run {{ target }}" command sets up such a server in order to display
-- stats on the dashboard.
--
-- You may also want to use this plugin to integrate S2E into a larger
-- system. The server could collect information about execution from different
-- S2E instances, filter them, and store them in a database.

add_plugin("WebServiceInterface")
pluginsConfig.WebServiceInterface = {
    statsUpdateInterval = 2
}

-------------------------------------------------------------------------------
-- This is the main execution tracing plugin.
-- It generates the ExecutionTracer.dat file in the s2e-last folder.
-- That files contains trace information in a binary format. Other plugins can
-- hook into ExecutionTracer in order to insert custom tracing data.
--
-- This is a core plugin, you most likely always want to have it.

add_plugin("ExecutionTracer")

-------------------------------------------------------------------------------
-- This plugin records events about module loads/unloads and stores them
-- in ExecutionTracer.dat.
-- This is useful in order to map raw program counters and pids to actual
-- module names.

add_plugin("ModuleTracer")

-------------------------------------------------------------------------------
-- This is a generic plugin that let other plugins communicate with each other.
-- It is a simple key-value store.
--
-- The plugin has several modes of operation:
--
-- 1. local: runs an internal store private to each instance (default)
-- 2. distributed: the plugin interfaces with an actual key-value store server.
-- This allows different instances of S2E to communicate with each other.

add_plugin("KeyValueStore")

-------------------------------------------------------------------------------
-- Records the program counter of executed translation blocks.
-- Generates a json coverage file. This file can be later processed by other
-- tools to generate line coverage information. Please refer to the S2E
-- documentation for more details.

add_plugin("TranslationBlockCoverage")
pluginsConfig.TranslationBlockCoverage = {
    writeCoverageOnStateKill = true
}

-------------------------------------------------------------------------------
-- Tracks execution of specific modules.
-- Analysis plugins are often interested only in small portions of the system,
-- typically the modules under analysis. This plugin filters out all core
-- events that do not concern the modules under analysis. This simplifies
-- code instrumentation.
-- Instead of listing individual modules, you can also track all modules by
-- setting configureAllModules = true

add_plugin("ModuleExecutionDetector")
pluginsConfig.ModuleExecutionDetector = {
    {% for m in modules %}
    mod_0 = {
        moduleName = "{{ m[0] }}",
        kernelMode = {% if m[1] %} true {% else %} false {% endif %},
    },
    {% endfor %}
}

-------------------------------------------------------------------------------
-- This plugin controls the forking behavior of S2E.

add_plugin("ForkLimiter")
pluginsConfig.ForkLimiter = {
    -- How many times each program counter is allowed to fork.
    -- -1 for unlimited.
    maxForkCount = -1,

    -- How many seconds to wait before allowing an S2E process
    -- to spawn a child. When there are many states, S2E may
    -- spawn itself into multiple processes in order to leverage
    -- multiple cores on the host machine. When an S2E process A spawns
    -- a process B, A and B each get half of the states.
    --
    -- In some cases, when states fork and terminate very rapidly,
    -- one can see flash crowds of S2E instances. This decreases
    -- execution efficiency. This parameter forces S2E to wait a few
    -- seconds so that more states can accumulate in an instance
    -- before spawning a process.
    processForkDelay = 5,
}

-------------------------------------------------------------------------------
-- This plugin tracks execution of processes.
-- This is the preferred way of tracking execution and will eventually replace
-- ModuleExecutionDetector.

add_plugin("ProcessExecutionDetector")
pluginsConfig.ProcessExecutionDetector = {
    moduleNames = {
        {% for p in processes %}
        "{{ p }}",
        {% endfor %}
    },
}

-------------------------------------------------------------------------------
-- Keeps for each state/process an updated map of all the loaded modules.
add_plugin("ModuleMap")


-------------------------------------------------------------------------------
-- Keeps for each process in ProcessExecutionDetector an updated map
-- of memory regions.
add_plugin("MemoryMap")

{% if use_cupa == true %}

-------------------------------------------------------------------------------
-- MultiSearcher is a top-level searcher that allows switching between
-- different sub-searchers.
add_plugin("MultiSearcher")

-- CUPA stands for Class-Uniform Path Analysis. It is a searcher that groups
-- states into classes. Each time the searcher needs to pick a state, it first
-- chooses a class, then picks a state in that class. Classes can further be
-- subdivided into subclasses.
--
-- The advantage of CUPA over other searchers is that it gives similar weights
-- to different parts of the program. If one part forks a lot, a random searcher
-- would most likely pick a state from that hotspot, decreasing the probability
-- of choosing another state that may have better chance of covering new code.
-- CUPA avoids this problem by grouping similar states together.

add_plugin("CUPASearcher")
pluginsConfig.CUPASearcher = {
    -- The order of classes is important, please refer to the plugin
    -- source code and documentation for details on how CUPA works.
    classes = {
        {% if use_seeds == true %}
        -- This is a special class that must be used first when the SeedSearcher
        -- is enabled. It ensures that seed state 0 is kept out of scheduling
        -- unless instructed by SeedSearcher.
        "seed",
        {% endif %}

        -- This ensures that states run for a certain amount of time.
        -- Otherwise too frequent state switching may decrease performance.
        "batch",

        {% if use_pov_generation %}
        -- This class is used with the Recipe plugin in order to prioritize
        -- states that have a high chance of containing a vulnerability.
        "group",
        {% endif %}

        -- A program under test may be composed of several binaries.
        -- We want to give equal chance to all binaries, even if some of them
        -- fork a lot more than others.
        "pagedir",

        -- Finally, group states by program counter at fork.
        "pc",
    },
    logLevel="info",
    enabled = true
}

{% endif %}

{% if use_seeds == true %}

-- Required dependency of SeedSearcher
add_plugin("MultiSearcher")

-------------------------------------------------------------------------------
-- The SeedSearcher plugin looks for new seeds in the seed directory and
-- schedules the seed fetching state whenever a new seed is available. This
-- searcher may be used in conjunction with a fuzzer in order to combine the
-- speed of a fuzzer with the efficiency of symbolic execution. Fuzzers can
-- quickly generate skeleton paths and symbolic execution can explore side
-- branches efficiently along these skeleton paths.
--
-- Note:
--   1. SeedSearcher must be used in conjunction with a suitable bootstrap.sh.
--   Everything is taken care of by s2e-env, just enable the use seeds option.
--
--   2. There will always be an S2E instance running, even if there are
--   otherwise no more states to run. This is because in seeding mode, state 0
--   never terminates, as it continuously tries to fetch new seeds.

add_plugin("SeedSearcher")
pluginsConfig.SeedSearcher = {
    enableSeeds = true,
    seedDirectory = "{{ project_dir }}/seeds",
}

-- The SeedScheduler plugin takes care of implementing the seed usage policies.
-- It decides when it is a good time to try new seeds, based on current
-- coverage, number of bugs found, etc. When it thinks that S2E is stuck and
-- does not make progress, this plugin will instruct SeedSearcher to schedule
-- a new seed.
add_plugin("SeedScheduler")
pluginsConfig.SeedScheduler = {
    -- Seeds with priority equal to or lower than the threshold are considered
    -- low priority. For CFE, high priorities range from 10 to 7 (various
    -- types of POVs and crashes), while normal test cases are from 6 and
    -- below. High priority seeds are scheduled asap, even if S2E is making
    -- progress.
    lowPrioritySeedThreshold = 6,
}

-- Required for SeedScheduler
add_plugin("TranslationBlockCoverage")
{% endif %}

-------------------------------------------------------------------------------
-- Function models help drastically reduce path explosion. A model is an
-- expression that efficiently encodes the behavior of a function. In imperative
-- languages, functions often have if-then-else branches and loops, which
-- may cause path explosion. A model compresses this into a single large
-- expression. Models are most suitable for side-effect-free functions that
-- fork a lot. Please refer to models.lua and the documentation for more details.

add_plugin("StaticFunctionModels")

pluginsConfig.StaticFunctionModels = {
  modules = {}
}

g_function_models = {}
safe_load('models.lua')
pluginsConfig.StaticFunctionModels.modules = g_function_models

{% if use_test_case_generator %}
-------------------------------------------------------------------------------
-- This generates test cases when a state crashes or terminates.
-- If symbolic inputs consist of symbolic files, the test case generator writes
-- concrete files in the S2E output folder. These files can be used to
-- demonstrate the crash in a program, added to a test suite, etc.

add_plugin("TestCaseGenerator")
pluginsConfig.TestCaseGenerator = {
    generateOnStateKill = true,
    generateOnSegfault = true
}
{% endif %}


{% if enable_pov_generation %}

-------------------------------------------------------------------------------
-- This plugin aggregates different sources of vulnerability information and
-- uses it to generate PoVs.

add_plugin("PovGenerationPolicy")

-------------------------------------------------------------------------------
-- The Recipe plugin continuously monitors execution and looks for states
-- that can be exploited. The most important marker of a vulnerability is
-- dereferencing a symbolic pointer. The recipe plugin then constrains that
-- symbolic pointer in a way that forces program execution into a state that
-- was negotiated with the CGC framework.

add_plugin("Recipe")
pluginsConfig.Recipe = {
    recipesDir = "{{ recipes_dir }}",
    logLevel = "warn"
}

-------------------------------------------------------------------------------
-- The stack monitor plugin instruments function calls and returns in order
-- to keep track of call stacks, stack frames, etc. Interested plugins can
-- use StackMonitor to get information about the current call stack.

add_plugin("StackMonitor")

-------------------------------------------------------------------------------
-- This plugin monitors call sites, i.e., pairs of source-destination program
-- counters. It is useful to recover information about indirect control flow,
-- which is hard to compute statically.

add_plugin("CallSiteMonitor")
pluginsConfig.CallSiteMonitor = {
    dumpInterval = 5,
}


{% endif %}

-- ========================================================================= --
-- ============== Target-specific configuration begins here. =============== --
-- ========================================================================= --

{% include '%s' % target_lua_template %}
