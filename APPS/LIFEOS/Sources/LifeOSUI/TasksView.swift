import LifeOSAPI
import LifeOSCore
import SwiftUI

/// Ejecutar: las acciones, con o sin hora.
///
/// Se agrupan por estado (en curso, por hacer, sin clasificar, hechas, descartadas)
/// porque así lo devuelve el servidor y así se lee lo que está en marcha. Marcar
/// una como hecha es un `PATCH` con la versión que ya teníamos: si cambió en otro
/// sitio, el servidor responde 409 y se avisa en vez de pisarlo.
public struct TasksView: View {
    @ObservedObject private var model: LifeOSModel

    public init(model: LifeOSModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            TasksContent(model: model)
        }
        .task { await model.loadTasks() }
    }
}

struct TasksContent: View {
    @ObservedObject var model: LifeOSModel

    var body: some View {
        VStack(alignment: .leading, spacing: LifeOSSpace.l) {
            header
            if model.taskDraft != nil {
                TaskForm(model: model)
            }
            list
        }
        .padding(.horizontal, LifeOSSpace.xl)
        .padding(.vertical, LifeOSSpace.xl)
        .frame(maxWidth: 820, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(LifeOSTheme.canvas)
    }

    private var header: some View {
        LifeOSScreenHeader(
            eyebrow: "Ejecutar · \(openCount) abiertas",
            title: "Lo que hay que hacer",
            detail: "Lo que viene de Google se marca como tal. Si allí desapareció o cambió en los dos sitios, se dice: no se decide solo."
        ) {
            HStack(spacing: LifeOSSpace.s) {
                filters
                if model.taskDraft == nil {
                    Button("Nueva acción") { model.startTask() }
                        .buttonStyle(LifeOSPrimaryButtonStyle())
                }
            }
        }
    }

    private var filters: some View {
        HStack(spacing: LifeOSSpace.xs) {
            ForEach(TaskFilter.allCases) { filter in
                Button {
                    model.taskFilter = filter
                } label: {
                    Text(filter.label)
                        .font(LifeOSFont.labelSmall)
                        .foregroundStyle(model.taskFilter == filter ? LifeOSTheme.brandOnSoft : LifeOSTheme.textSecondary)
                        .padding(.horizontal, LifeOSSpace.m)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(model.taskFilter == filter ? LifeOSTheme.brandSoft : LifeOSTheme.surface)
                        )
                        .overlay(Capsule().strokeBorder(LifeOSTheme.borderSubtle, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var openCount: Int {
        model.tasks.filter(\.isOpen).count
    }

    @ViewBuilder
    private var list: some View {
        if model.visibleTasks.isEmpty {
            LifeOSCard {
                LifeOSEmptyState(
                    systemImage: model.taskFilter == .done ? "checkmark.circle" : "checklist",
                    title: model.taskFilter == .done ? "Nada terminado por aquí" : "Nada pendiente",
                    detail: model.taskFilter == .done
                        ? "Cuando marques algo como hecho aparecerá aquí."
                        : "Crea una acción o captura lo que tengas en la cabeza."
                )
            }
        } else {
            VStack(alignment: .leading, spacing: LifeOSSpace.l) {
                ForEach(model.visibleTasksByStatus, id: \.status) { group in
                    LifeOSCard {
                        VStack(alignment: .leading, spacing: LifeOSSpace.m) {
                            LifeOSSectionHeader(statusTitle(group.status), count: group.items.count)
                            VStack(alignment: .leading, spacing: LifeOSSpace.s) {
                                ForEach(group.items) { task in
                                    TaskRow(task: task, model: model)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func statusTitle(_ status: String) -> String {
        model.tasks.first { $0.status == status }?.statusLabel ?? status
    }
}

/// Alta rápida de una acción: lo mínimo que hace falta para que exista.
struct TaskForm: View {
    @ObservedObject var model: LifeOSModel
    @Environment(\.lifeOSFlatSurfaces) private var renderMode

    var body: some View {
        LifeOSCard(accent: LifeOSTheme.brand) {
            VStack(alignment: .leading, spacing: LifeOSSpace.m) {
                LifeOSSectionHeader("Nueva acción")
                LifeOSField("¿Qué hay que hacer?", text: binding(\.title))
                HStack(alignment: .bottom, spacing: LifeOSSpace.l) {
                    VStack(alignment: .leading, spacing: LifeOSSpace.xs) {
                        Text("Prioridad")
                            .font(LifeOSFont.caption)
                            .foregroundStyle(LifeOSTheme.textTertiary)
                        PriorityPicker(value: binding(\.priority))
                    }
                    VStack(alignment: .leading, spacing: LifeOSSpace.xs) {
                        Text("Vence (opcional)")
                            .font(LifeOSFont.caption)
                            .foregroundStyle(LifeOSTheme.textTertiary)
                        if renderMode {
                            Text(TimeFormatting.dateAndTime(model.taskDraft?.dueDate ?? Date()))
                                .font(LifeOSFont.body)
                                .foregroundStyle(LifeOSTheme.textPrimary)
                                .padding(.horizontal, LifeOSSpace.m)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: LifeOSRadius.md, style: .continuous)
                                        .fill(LifeOSTheme.field)
                                )
                        } else {
                            DatePicker(
                                "",
                                selection: Binding(
                                    get: { model.taskDraft?.dueDate ?? Date() },
                                    set: { model.taskDraft?.dueDate = $0 }
                                ),
                                displayedComponents: [.date]
                            )
                            .labelsHidden()
                            .datePickerStyle(.field)
                        }
                    }
                    VStack(alignment: .leading, spacing: LifeOSSpace.xs) {
                        Text("Contexto (opcional)")
                            .font(LifeOSFont.caption)
                            .foregroundStyle(LifeOSTheme.textTertiary)
                        LifeOSField("Casa, trabajo…", text: binding(\.context))
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: LifeOSSpace.s) {
                    Button(model.taskDraft?.dueDate == nil ? "Poner fecha" : "Quitar fecha") {
                        model.taskDraft?.dueDate = model.taskDraft?.dueDate == nil ? Date() : nil
                    }
                    .buttonStyle(LifeOSGhostButtonStyle())
                    Spacer(minLength: 0)
                    Button("Cancelar") { model.cancelTaskDraft() }
                        .buttonStyle(LifeOSGhostButtonStyle())
                    Button("Crear acción") { Task { await model.saveTask() } }
                        .buttonStyle(LifeOSPrimaryButtonStyle())
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!model.canSaveTask)
                }
            }
        }
    }

    private func binding<Value>(_ key: WritableKeyPath<TaskDraft, Value>) -> Binding<Value> {
        Binding(
            get: { model.taskDraft?[keyPath: key] ?? TaskDraft()[keyPath: key] },
            set: { model.taskDraft?[keyPath: key] = $0 }
        )
    }
}

/// Prioridad de 1 a 5, con la misma idea que el ánimo del diario: se vuelve a
/// pulsar para dejarla en el valor por defecto.
struct PriorityPicker: View {
    @Binding var value: Int

    var body: some View {
        HStack(spacing: LifeOSSpace.xs) {
            ForEach(1...5, id: \.self) { level in
                Button {
                    value = level
                } label: {
                    Circle()
                        .fill(level <= value ? tint(level) : LifeOSTheme.elevated)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle().strokeBorder(
                                level <= value ? Color.clear : LifeOSTheme.borderSubtle,
                                lineWidth: 1
                            )
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(priorityLabel(level))
            }
            Text(priorityLabel(value))
                .font(LifeOSFont.caption)
                .foregroundStyle(LifeOSTheme.textTertiary)
        }
    }

    private func tint(_ level: Int) -> Color {
        level <= 2 ? LifeOSTheme.warning : LifeOSTheme.brand
    }

    private func priorityLabel(_ level: Int) -> String {
        switch level {
        case 1: return "Urgente"
        case 2: return "Alta"
        case 3: return "Normal"
        case 4: return "Baja"
        default: return "Algún día"
        }
    }
}
