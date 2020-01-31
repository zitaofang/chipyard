//See LICENSE for license details.

package firesim.firesim

import chisel3._

import freechips.rocketchip.config.{Field, Config}
import freechips.rocketchip.diplomacy.{LazyModule}
import freechips.rocketchip.devices.debug.HasPeripheryDebugModuleImp
import freechips.rocketchip.subsystem.{CanHaveMasterAXI4MemPortModuleImp}
import sifive.blocks.devices.uart.{HasPeripheryUARTModuleImp, UART}

import testchipip.{HasPeripherySerialModuleImp, HasPeripheryBlockDeviceModuleImp}
import icenet.HasPeripheryIceNICModuleImpValidOnly

import junctions.{NastiKey, NastiParameters}
import midas.models.{FASEDBridge, AXI4EdgeSummary, CompleteConfig}
import firesim.bridges._
import firesim.configs.MemModelKey
import firesim.util.RegisterBridgeBinder
import tracegen.HasTraceGenTilesModuleImp

class WithTiedOffDebug extends RegisterBridgeBinder({ case target: HasPeripheryDebugModuleImp =>
  target.debug.foreach(_.clockeddmi.foreach({ cdmi =>
    cdmi.dmi.req.valid := false.B
    cdmi.dmi.req.bits := DontCare
    cdmi.dmi.resp.ready := false.B
    cdmi.dmiClock := false.B.asClock
    cdmi.dmiReset := false.B
  }))
  Seq()
})

class WithSerialBridge extends RegisterBridgeBinder({
  case target: HasPeripherySerialModuleImp => Seq(SerialBridge(target.serial)(target.p)) 
})

class WithNICBridge extends RegisterBridgeBinder({
  case target: HasPeripheryIceNICModuleImpValidOnly => Seq(NICBridge(target.net)(target.p)) 
})

case object TieOffUART extends Field(false)
class WithUARTBridge extends RegisterBridgeBinder({
  case target: HasPeripheryUARTModuleImp => if (target.p(TieOffUART)) {
    target.uart.map(u => UART.tieoff(u))
    Seq()
  } else {
    target.uart.map(u => UARTBridge(u)(target.p))
  }
})
class WithTieOffUART extends Config((site, here, up) => { case TieOffUART => true })


case object TieOffBlockDevice extends Field(false)
class WithBlockDeviceBridge extends RegisterBridgeBinder({
  case target: HasPeripheryBlockDeviceModuleImp => if (target.p(TieOffBlockDevice)) {
     target.bdev.req.ready := true.B
     target.bdev.data.ready := true.B
     target.bdev.resp.valid := false.B
     target.bdev.resp.bits := DontCare
     target.bdev.info.nsectors := 1.U
     target.bdev.info.max_req_len := 128.U
     Seq()
   } else {
     Seq(BlockDevBridge(target.bdev, target.reset.toBool)(target.p))
   }
})
class WithTieOffBlockDevice extends Config((site, here, up) => { case TieOffBlockDevice => true })


case object AXI4ReqChannels extends Field(false)
class WithAXI4ReqPrintfs extends Config((site, here, up) => { case AXI4ReqChannels => true })

class WithFASEDBridge extends RegisterBridgeBinder({
  case t: CanHaveMasterAXI4MemPortModuleImp =>
    implicit val p = t.p
    val tCycle = RegInit(0.U(32.W))
    tCycle := tCycle + 1.U
    val axi4 = t.mem_axi4.head.head
    when (axi4.r.valid){ printf(midas.targetutils.SynthesizePrintf("R %b %d %d %b\n", axi4.r.ready, axi4.r.bits.id, axi4.r.bits.resp, axi4.r.bits.last)) }
    when (axi4.b.valid){ printf(midas.targetutils.SynthesizePrintf("B %b %d %d\n", axi4.b.ready, axi4.b.bits.id, axi4.b.bits.resp)) }
    if (p(AXI4ReqChannels)) {
      when (axi4.ar.valid){ printf(midas.targetutils.SynthesizePrintf("AR %b %d %d %b\n", axi4.ar.ready, axi4.ar.bits.id, axi4.ar.bits.len, axi4.ar.bits.addr)) }
      when (axi4.aw.valid){ printf(midas.targetutils.SynthesizePrintf("AW %b %d %d %b\n", axi4.aw.ready, axi4.aw.bits.id, axi4.aw.bits.len, axi4.aw.bits.addr)) }
      when (axi4. w.valid){ printf(midas.targetutils.SynthesizePrintf("W  %b %b\n", axi4.w.ready , axi4.w.bits.last)) }
    }

    (t.mem_axi4 zip t.outer.memAXI4Node).flatMap({ case (io, node) =>
      (io zip node.in).map({ case (axi4Bundle, (_, edge)) =>
        val nastiKey = NastiParameters(axi4Bundle.r.bits.data.getWidth,
                                       axi4Bundle.ar.bits.addr.getWidth,
                                       axi4Bundle.ar.bits.id.getWidth)
        FASEDBridge(axi4Bundle, t.reset.toBool,
          CompleteConfig(p(firesim.configs.MemModelKey), nastiKey, Some(AXI4EdgeSummary(edge))))
      })
    }).toSeq
})

case object TieOffTracerV extends Field(false)
class WithTracerVBridge extends RegisterBridgeBinder({
  case target: HasTraceIOImp => if (target.p(TieOffTracerV)) {
    Seq()
  } else {
    TracerVBridge(target.traceIO)(target.p)
  }
})
class WithTieOffTracerV extends Config((site, here, up) => { case TieOffTracerV => true })

class WithTraceGenBridge extends RegisterBridgeBinder({
  case target: HasTraceGenTilesModuleImp =>
    Seq(GroundTestBridge(target.success)(target.p))
})

// Shorthand to register all of the provided bridges above
class WithDefaultFireSimBridges extends Config(
  new WithTiedOffDebug ++
  new WithSerialBridge ++
  new WithNICBridge ++
  new WithUARTBridge ++
  new WithBlockDeviceBridge ++
  new WithFASEDBridge ++
  new WithTracerVBridge
)

