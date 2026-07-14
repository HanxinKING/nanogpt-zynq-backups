<AutoPilot:project xmlns:AutoPilot="com.autoesl.autopilot.project" top="tiled_matmul_kernel" name="tiled_matmul" ideType="classic">
    <files>
        <file name="../../source/tiled_matmul/tiled_matmul.cpp" sc="0" tb="false" cflags="" csimflags="" blackbox="false"/>
        <file name="../../source/tiled_matmul/tiled_matmul.hpp" sc="0" tb="false" cflags="" csimflags="" blackbox="false"/>
        <file name="../../source/common/hls_common.hpp" sc="0" tb="false" cflags="" csimflags="" blackbox="false"/>
        <file name="../../source/tiled_matmul/tb_tiled_matmul.cpp" sc="0" tb="1" cflags="-Wno-unknown-pragmas" csimflags="" blackbox="false"/>
    </files>
    <solutions>
        <solution name="sol1" status=""/>
    </solutions>
    <Simulation argv="">
        <SimFlow name="csim" setup="false" optimizeCompile="false" clean="false" ldflags="" mflags=""/>
    </Simulation>
</AutoPilot:project>
