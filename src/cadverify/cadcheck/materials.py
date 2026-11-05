"""The printed materials G6 knows: what each datasheet says, and the limits drawn from it.

Every number has its source. The stiffness and the strength are the bending values of the
manufacturer's datasheet (ISO 178), at 100% infill: a part that flexes bends, and a tensile
coupon says less about it. `strain_once` is the strain at that strength, the elastic limit in
flexure; `strain_repeated` is half of it, the working limit for what flexes again and again.
Between layers the limit is multiplied by `z_factor`: the datasheets' Z coupons say little of what
a layer does (PLA Basic's Z strength is 89% of its X-Y), and independent tests find far less.

No datasheet here gives Poisson's ratio. POISSON is the usual value for a glassy polymer, not a
measurement; tests/test_behaviour.py bounds what moving it from 0.30 to 0.40 does to a cantilever.
"""

from __future__ import annotations

from dataclasses import dataclass

POISSON = 0.35
GRAVITY = 9.81

_PLA_TDS = (
    "Bambu Lab PLA Basic Technical Data Sheet V2.0, "
    "https://cdn.shopify.com/s/files/1/0380/5149/files/Bambu_PLA_Basic_Technical_Data_Sheet.pdf"
)
_PETG_TDS = (
    "Bambu Lab PETG Basic Technical Data Sheet V2.0, "
    "https://www.additive-x.com/shop/mpattachments/file/viewonline/id/580/product_id/2330"
)
_PETG_CF_TDS = (
    "Bambu Lab PETG-CF Technical Data Sheet V2.0, "
    "https://www.additive-x.com/shop/mpattachments/file/viewonline/id/596/product_id/2346"
)
_REPEATED = (
    "A working stress for repeated use of 'typically about 50% of its elastic limit' (read in a "
    "search excerpt: the page refuses automated readers): Injection molding design fundamentals: "
    "snap-fits for plastic parts, PlasticsToday, https://www.plasticstoday.com/injection-molding/"
    "injection-molding-design-fundamentals-snap-fits-plastic-parts"
)
_Z_HALF = (
    "Allowable strain halved for a part stressed along Z: How to Design Snap Fit Components, "
    "Core77, https://www.core77.com/posts/65318/How-to-Design-Snap-Fit-Components"
)
_Z_PETG = (
    "PETG 127.9% stronger along X than along Z on a Bambu Lab P1S at 0.2 mm and 100% infill: "
    "Mechanical and FEA comparison of FDM, Sacramento State thesis, "
    "https://scholars.csus.edu/esploro/outputs/graduate/Mechanical-and-FEA-comparison-of-FDM/"
    "99258311232901671"
)


@dataclass(frozen=True)
class Material:
    name: str
    density_g_cm3: float
    bending_modulus_mpa: float
    bending_strength_mpa: float
    z_factor: float  # of the strain limit, for tension between layers
    sources: tuple[str, ...]

    @property
    def strain_once(self) -> float:
        """The strain limit of what bends a few times (a snap as it goes in), a fraction."""
        return self.bending_strength_mpa / self.bending_modulus_mpa

    @property
    def strain_repeated(self) -> float:
        """The strain limit of what bends again and again, or stays loaded, a fraction."""
        return self.strain_once / 2

    def public(self) -> dict:
        return {
            "name": self.name,
            "density_g_cm3": self.density_g_cm3,
            "bending_modulus_mpa": self.bending_modulus_mpa,
            "bending_strength_mpa": self.bending_strength_mpa,
            "strain_once_pct": round(100 * self.strain_once, 2),
            "strain_repeated_pct": round(100 * self.strain_repeated, 2),
            "z_factor": self.z_factor,
            "poisson_assumed": POISSON,
            "sources": list(self.sources),
        }


MATERIALS = {
    "PLA": Material("PLA", 1.24, 2750.0, 76.0, 0.5, (_PLA_TDS, _REPEATED, _Z_HALF)),
    "PETG": Material("PETG", 1.25, 1790.0, 81.0, 0.44, (_PETG_TDS, _REPEATED, _Z_PETG)),
    "PETG-CF": Material("PETG-CF", 1.25, 2890.0, 83.0, 0.44, (_PETG_CF_TDS, _REPEATED, _Z_PETG)),
}
