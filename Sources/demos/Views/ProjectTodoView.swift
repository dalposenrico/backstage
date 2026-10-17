import SwiftUI

struct ProjectTodoSection: View {
    let project: Project
    @EnvironmentObject private var todoStore: ProjectTodoStore
    @State private var newTodo = ""

    private var todos: [ProjectTodo] { todoStore.todos(for: project) }
    private var completedCount: Int { todos.filter(\.isCompleted).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("To-Do")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primaryText)
                    Text(todos.isEmpty ? "Capture the small steps for this project" : "\(completedCount) of \(todos.count) completed")
                        .font(.system(size: 10))
                        .foregroundColor(.tertiaryText)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                TextField("Add a task…", text: $newTodo)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit(addTodo)
                Button(action: addTodo) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundColor(newTodo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .tertiaryText : .accent)
                .disabled(newTodo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Color.elevatedBg)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).stroke(Color.subtleBorder) }

            if !todos.isEmpty {
                VStack(spacing: 2) {
                    ForEach(todos) { todo in
                        HStack(spacing: 9) {
                            Button { todoStore.toggle(todo, for: project) } label: {
                                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 14))
                                    .foregroundColor(todo.isCompleted ? .accent : .tertiaryText)
                            }
                            .buttonStyle(.plain)

                            Text(todo.title)
                                .font(.system(size: 12))
                                .foregroundColor(todo.isCompleted ? .tertiaryText : .primaryText)
                                .strikethrough(todo.isCompleted)
                            Spacer()
                            Button { todoStore.remove(todo, from: project) } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.tertiaryText)
                            }
                            .buttonStyle(.plain)
                            .help("Delete task")
                        }
                        .padding(.horizontal, 4)
                        .frame(minHeight: 30)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.surfaceBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.subtleBorder, lineWidth: 1) }
        .padding(.vertical, 10)
    }

    private func addTodo() {
        todoStore.add(newTodo, to: project)
        newTodo = ""
    }
}
