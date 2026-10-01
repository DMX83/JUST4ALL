import Foundation

import LifeOSAPI

/// Datos de ejemplo para la revisión de diseño.
///
/// Se construyen **decodificando JSON igual que lo hace la app** (`LifeOSJSON`),
/// no con inicializadores a mano: así los ejemplos no se desvían del contrato y,
/// de paso, el render falla si el contrato cambia.
enum SampleData {
    static func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T {
        do {
            return try LifeOSJSON.decoder().decode(T.self, from: Data(json.utf8))
        } catch {
            fatalError("Ejemplo de \(T.self) no decodificable: \(error)")
        }
    }

    /// La respuesta de `GET /agenda` de un día con las tres cosas.
    static var agendaWeek: AgendaDay {
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let start = now.addingTimeInterval(3600 * 3)
        let end = start.addingTimeInterval(3600)
        let focusStart = now.addingTimeInterval(3600 * 5)
        let focusEnd = focusStart.addingTimeInterval(5400)
        let dueDate = now.addingTimeInterval(3600 * 8)
        let eventId = UUID().uuidString
        let taskId = UUID().uuidString
        let duplicateTaskId = UUID().uuidString

        let json = """
        {
          "events": [
            {
              "id": "\(eventId)",
              "title": "Reunión con el cliente",
              "starts_at": "\(formatter.string(from: start))",
              "ends_at": "\(formatter.string(from: end))",
              "all_day": false,
              "timezone": "Europe/Madrid",
              "location": "Videollamada",
              "notes": "",
              "status": "scheduled",
              "sensitivity": "standard",
              "recurrence_rule": "",
              "reminders": [10],
              "focus_target_id": null,
              "version": 3,
              "recurrence_id": null,
              "series": false,
              "focus_target": null,
              "source": "google",
              "external_id": "g-1",
              "external_state": "synced",
              "origin": {"id": "cal-1", "label": "Calendar · Trabajo", "kind": "calendar", "direction": "pull"}
            },
            {
              "id": "\(taskId)-focus",
              "title": "Preparar la propuesta",
              "starts_at": "\(formatter.string(from: focusStart))",
              "ends_at": "\(formatter.string(from: focusEnd))",
              "all_day": false,
              "timezone": "Europe/Madrid",
              "location": "",
              "notes": "",
              "status": "scheduled",
              "sensitivity": "standard",
              "recurrence_rule": "FREQ=WEEKLY",
              "reminders": [],
              "focus_target_id": "\(taskId)",
              "version": 1,
              "recurrence_id": "series-1",
              "series": true,
              "focus_target": {"id": "\(taskId)", "kind": "task", "title": "Preparar la propuesta"},
              "source": "manual",
              "external_id": null,
              "external_state": "",
              "origin": null
            }
          ],
          "tasks": [
            {
              "id": "\(taskId)",
              "title": "Preparar la propuesta",
              "priority": 2,
              "due_date": null,
              "estimate_minutes": 90,
              "context": "Trabajo",
              "scheduled_start": "\(formatter.string(from: focusStart))",
              "scheduled_end": "\(formatter.string(from: focusEnd))",
              "recurrence_rule": "",
              "reminders": [],
              "energy": "high",
              "status": "doing",
              "objective_ids": [],
              "blocked": false,
              "completed_at": null,
              "version": 4,
              "source": "manual",
              "external_id": null,
              "external_state": "",
              "origin": null
            }
          ],
          "due_tasks": [
            {
              "id": "\(dueDate.timeIntervalSince1970)",
              "title": "Enviar el informe de gastos",
              "priority": 1,
              "due_date": "\(formatter.string(from: dueDate))",
              "estimate_minutes": null,
              "context": "Hacienda",
              "scheduled_start": null,
              "scheduled_end": null,
              "recurrence_rule": "",
              "reminders": [],
              "energy": "any",
              "status": "todo",
              "objective_ids": [],
              "blocked": false,
              "completed_at": null,
              "version": 2,
              "source": "google",
              "external_id": "g-task-9",
              "external_state": "conflict",
              "origin": {"id": "list-1", "label": "Tasks · Compras", "kind": "tasks", "direction": "pull"}
            }
          ],
          "duplicates": [
            {
              "id": "\(duplicateTaskId)",
              "task_id": "\(duplicateTaskId)",
              "event_id": "\(eventId)",
              "title": "Reunión con el cliente",
              "event_title": "Reunión con el cliente",
              "task_title": "Llamar al cliente",
              "at": "\(formatter.string(from: start))",
              "status": "suggested",
              "reason": "Mismo nombre y misma hora"
            }
          ]
        }
        """
        return decode(AgendaDay.self, json)
    }

    /// Unas cuantas acciones, con los dos orígenes y un par de estados.
    static var tasks: [LifeOSTask] {
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let json = """
        [
          {
            "id": "t-doing",
            "title": "Preparar la propuesta",
            "priority": 2,
            "due_date": "\(formatter.string(from: now.addingTimeInterval(3600)))",
            "estimate_minutes": 90,
            "context": "Trabajo",
            "scheduled_start": null,
            "scheduled_end": null,
            "recurrence_rule": "",
            "reminders": [],
            "energy": "high",
            "status": "doing",
            "objective_ids": [],
            "blocked": false,
            "completed_at": null,
            "version": 4,
            "source": "manual",
            "external_id": null,
            "external_state": "",
            "origin": null
          },
          {
            "id": "t-todo",
            "title": "Enviar el informe de gastos",
            "priority": 1,
            "due_date": "\(formatter.string(from: now.addingTimeInterval(-86_400)))",
            "estimate_minutes": null,
            "context": "Hacienda",
            "scheduled_start": null,
            "scheduled_end": null,
            "recurrence_rule": "",
            "reminders": [],
            "energy": "any",
            "status": "todo",
            "objective_ids": [],
            "blocked": false,
            "completed_at": null,
            "version": 2,
            "source": "google",
            "external_id": "g-task-9",
            "external_state": "conflict",
            "origin": {"id": "list-1", "label": "Tasks · Compras", "kind": "tasks", "direction": "pull"}
          },
          {
            "id": "t-done",
            "title": "Llamar al gestor",
            "priority": 3,
            "due_date": null,
            "estimate_minutes": null,
            "context": "",
            "scheduled_start": null,
            "scheduled_end": null,
            "recurrence_rule": "",
            "reminders": [],
            "energy": "any",
            "status": "done",
            "objective_ids": [],
            "blocked": false,
            "completed_at": "\(formatter.string(from: now.addingTimeInterval(-7200)))",
            "version": 5,
            "source": "manual",
            "external_id": null,
            "external_state": "",
            "origin": null
          }
        ]
        """
        return decode([LifeOSTask].self, json)
    }

    /// La cronología de unos días, con varios tipos.
    static var timeline: Timeline {
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let json = """
        {
          "start": "\(formatter.string(from: now.addingTimeInterval(-604_800)))",
          "end": "\(formatter.string(from: now))",
          "days": 7,
          "items": [
            {
              "id": "j1", "kind": "journal", "title": "Diario · Tu día, por escrito",
              "occurred_at": "\(formatter.string(from: now))",
              "detail": "Cerré el informe y quedé con Ana el jueves", "ref_id": "j1", "sensitive": true
            },
            {
              "id": "t1", "kind": "task", "title": "Enviar el informe de gastos",
              "occurred_at": "\(formatter.string(from: now.addingTimeInterval(-3600)))",
              "detail": "venció ayer", "ref_id": "t1", "sensitive": false
            },
            {
              "id": "e1", "kind": "event", "title": "Reunión con el cliente",
              "occurred_at": "\(formatter.string(from: now.addingTimeInterval(-7200)))",
              "detail": "Videollamada", "ref_id": "e1", "sensitive": false
            },
            {
              "id": "c1", "kind": "capture", "title": "Captura · llamar al fisio",
              "occurred_at": "\(formatter.string(from: now.addingTimeInterval(-86_400)))",
              "detail": "bandeja", "ref_id": "c1", "sensitive": false
            },
            {
              "id": "d1", "kind": "decision", "title": "Renovar el contrato de hosting",
              "occurred_at": "\(formatter.string(from: now.addingTimeInterval(-172_800)))",
              "detail": "elegido: proveedor actual", "ref_id": "d1", "sensitive": false
            }
          ],
          "counts": {"journal": 1, "task": 1, "event": 1, "capture": 1, "decision": 1}
        }
        """
        return decode(Timeline.self, json)
    }

    static var searchResults: SearchResults {
        let json = """
        {
          "query": "informe",
          "results": [
            {"id": "t1", "kind": "task", "title": "Enviar el informe de gastos", "excerpt": "Hacienda · vence ayer", "sensitivity": "standard"},
            {"id": "j1", "kind": "journal", "title": "Notas sueltas", "excerpt": "…Cerré el informe y quedé con Ana…", "sensitivity": "sensitive"},
            {"id": "d1", "kind": "decision", "title": "Formato del informe mensual", "excerpt": "elegido: PDF firmado", "sensitivity": "standard"}
          ]
        }
        """
        return decode(SearchResults.self, json)
    }
}
