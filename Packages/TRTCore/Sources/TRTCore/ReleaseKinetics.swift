import Foundation

/// Modelo: liberação de ésteres a partir de depósito intramuscular oleoso.
///
/// Funções puras, sem estado e sem I/O. Tempo em horas, constantes em h⁻¹.
///
/// Só produz saídas normalizadas: a concentração absoluta exige C(t) = (F·D/V_d)·f(k_a, k_e, t), e
/// biodisponibilidade de depósito (F) e volume de distribuição (V_d) não são publicados para a maioria
/// dos compostos. Ao normalizar (fração liberada ou C/C_max) esse fator se cancela e o resultado
/// passa a depender apenas de k_a, o único parâmetro que o catálogo contém.
public enum ReleaseKinetics {
    /// Meias-vidas de eliminação varridas como parâmetro de sensibilidade (k_e não é constante fixa).
    public static let eliminationHalfLivesHours: [Double] = [1, 4.3, 12, 24]

    /// Abaixo disso, |k_a − k_e| é tratado como degenerado e usa-se o caso-limite.
    public static let degenerateTolerance = 1e-9

    /// k = ln(2) / t½. Para depósito oleoso, a meia-vida tabelada é de absorção (condição flip-flop, k_a ≪ k_e).
    public static func rate(halfLifeHours: Double) -> Double {
        log(2) / halfLifeHours
    }

    /// Constante de absorção k_a [h⁻¹].
    public static func absorptionRate(halfLifeHours: Double) -> Double {
        rate(halfLifeHours: halfLifeHours)
    }

    /// Liberação cumulativa F_lib(t) = 1 − exp(−k_a·t). Saída primária: depende só de k_a.
    public static func cumulativeRelease(_ t: Double, ka: Double) -> Double {
        t <= 0 ? 0 : -expm1(-ka * t)
    }

    public static func cumulativeRelease(_ t: [Double], ka: Double) -> [Double] {
        t.map { cumulativeRelease($0, ka: ka) }
    }

    /// Função de Bateman (monocompartimental, absorção de 1ª ordem), sem o fator F·D/V_d:
    /// C_bruto(t) = k_a/(k_a − k_e) · (exp(−k_e·t) − exp(−k_a·t)).
    /// Com |k_a − k_e| < 1e−9 usa o caso-limite C(t) = k·t·exp(−k·t).
    public static func batemanRaw(_ t: Double, ka: Double, ke: Double) -> Double {
        guard t > 0 else { return 0 }
        if abs(ka - ke) < degenerateTolerance {
            return ka * t * exp(-ka * t)
        }
        return ka / (ka - ke) * (exp(-ke * t) - exp(-ka * t))
    }

    /// t_max = ln(k_a/k_e) / (k_a − k_e); no caso degenerado, 1/k. Depende também de k_e.
    public static func tMax(ka: Double, ke: Double) -> Double {
        if abs(ka - ke) < degenerateTolerance { return 1 / ka }
        return log(ka / ke) / (ka - ke)
    }

    /// max(C_bruto), no t_max analítico.
    public static func batemanPeak(ka: Double, ke: Double) -> Double {
        batemanRaw(tMax(ka: ka, ke: ke), ka: ka, ke: ke)
    }

    /// C_norm(t) = C_bruto(t) / max(C_bruto). Saída secundária: requer k_e.
    public static func batemanNormalized(_ t: Double, ka: Double, ke: Double) -> Double {
        batemanRaw(t, ka: ka, ke: ke) / batemanPeak(ka: ka, ke: ke)
    }

    public static func batemanNormalized(_ t: [Double], ka: Double, ke: Double) -> [Double] {
        let peak = batemanPeak(ka: ka, ke: ke)
        return t.map { batemanRaw($0, ka: ka, ke: ke) / peak }
    }

    /// Tempo para liberar uma fração da dose: −ln(1 − fração) / k_a. t_90 = ln(10)/k_a; t_99 = ln(100)/k_a.
    public static func timeToFraction(ka: Double, fraction: Double) -> Double {
        -log1p(-fraction) / ka
    }

    /// Correção de peso do éster: D_pai = D_injetada · (doseAtivaPercentual / 100).
    /// Não altera curvas normalizadas; só importa ao comparar doses nominais diferentes.
    public static func parentDose(injected: Double, activeDosePercent: Double) -> Double {
        injected * activeDosePercent / 100
    }
}
