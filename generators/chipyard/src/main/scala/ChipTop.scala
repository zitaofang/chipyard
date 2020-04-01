package chipyard

import chisel3._

import scala.collection.mutable.{ArrayBuffer}

import freechips.rocketchip.config.{Parameters, Field}
import freechips.rocketchip.diplomacy.{LazyModule}
import freechips.rocketchip.util.{ResetCatchAndSync}
import chipyard.config.ConfigValName._
import chipyard.iobinders.{IOBinders, TestHarnessFunction, IOBinderTuple}

import barstools.iocell.chisel._

case object BuildSystem extends Field[Parameters => RawModule]((p: Parameters) => Module(LazyModule(new DigitalTop()(p)).suggestName("system").module))

case object ChipTopAddResetSync extends Field[Boolean](false)

/**
 * The base class used for building chips. This constructor instantiates a module specified by the BuildSystem parameter,
 * named "system", which is an instance of DigitalTop by default. The default clock and reset for "system" are set by two
 * wires, "systemClock" and "systemReset", which are intended to be driven by traits mixed-in with this base class.
 */
abstract class BaseChipTop()(implicit val p: Parameters) extends RawModule with HasTestHarnessFunctions {

  // A publicly accessible list of IO cells (useful for a floorplanning tool, for example)
  val iocells = ArrayBuffer.empty[IOCell]
  // A list of functions to call in the test harness
  val harnessFunctions = ArrayBuffer.empty[TestHarnessFunction]
  // The system clock
  val systemClock = Wire(Input(Clock()))
  // The system reset (synchronous to clock)
  val systemReset = Wire(Input(Bool()))

  // The system module specified by BuildSystem
  val system = withClockAndReset(systemClock, systemReset) { p(BuildSystem)(p) }

  // Call all of the IOBinders and provide them with a default clock and reset
  withClockAndReset(systemClock, systemReset) {
    val (_ports, _iocells, _harnessFunctions) = p(IOBinders).values.map(_(system)).flatten.unzip3
    // We ignore _ports for now...
    iocells ++= _iocells.flatten
    harnessFunctions ++= _harnessFunctions.flatten
  }

}

/**
 * A simple clock and reset implementation that punches out clock and reset ports with the same
 * names as the implicit clock and reset for standard Module classes. If p(ChipTopParams).addResetSync
 * is false (default), reset is synchronous to clock, which may not be a good idea to use for tapeouts.
 * Setting this to true will add a ResetCatchAndSync module before reset.
 */
trait HasChipTopSimpleClockAndReset { this: BaseChipTop =>

  val resetCore = if (p(ChipTopAddResetSync)) {
    val asyncResetCore = Wire(Input(Bool()))
    systemReset := ResetCatchAndSync(systemClock, asyncResetCore)
    asyncResetCore
  } else {
    systemReset
  }

  val (clock, systemClockIO) = IOCell.generateIOFromSignal(systemClock, Some("iocell_clock"))
  val (reset, systemResetIO) = IOCell.generateIOFromSignal(resetCore, Some("iocell_reset"))

  iocells ++= systemClockIO
  iocells ++= systemResetIO

  // Add a TestHarnessFunction that connects clock and reset
  harnessFunctions += { (th: TestHarness) => {
    // Connect clock; it's not done implicitly with RawModule
    clock := th.clock
    // Connect reset; it's not done implicitly with RawModule
    // Note that we need to use dutReset, not harnessReset
    reset := th.dutReset
    Nil
  } }

}

class ChipTop()(implicit p: Parameters) extends BaseChipTop()(p)
  with HasChipTopSimpleClockAndReset

