import SwiftUI
import AppKit

// Section with header and content items
struct GoalSection: Identifiable {
    let id = UUID()
    var title: String
    var items: [String]  // Sub-bullets or content lines

    var accentColor: Color {
        let colors: [Color] = [
            .blue, .purple, .pink, .orange, .green, .teal, .indigo, .mint
        ]
        var hash = 0
        for char in title.unicodeScalars {
            hash = hash &+ Int(char.value)
        }
        return colors[abs(hash) % colors.count]
    }
}

// Visual Goals view with sections
struct EditableGoalsView: View {
    @ObservedObject var todoList: TodoList
    @State private var isEditing: Bool = false
    @State private var editText: String = ""
    @FocusState private var isFocused: Bool

    // Parse markdown into sections (headers with their content)
    private var sections: [GoalSection] {
        let lines = todoList.goals.components(separatedBy: .newlines)
        var result: [GoalSection] = []
        var currentSection: GoalSection? = nil
        var standaloneItems: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                continue
            }

            // Check for bold headers: **text** or **text** #tag
            if trimmed.hasPrefix("**"), let endRange = trimmed.range(of: "**", range: trimmed.index(trimmed.startIndex, offsetBy: 2)..<trimmed.endIndex) {
                // Save previous section
                if let section = currentSection {
                    result.append(section)
                }
                // Save standalone items as "General" section
                if !standaloneItems.isEmpty && currentSection == nil {
                    result.append(GoalSection(title: "General", items: standaloneItems))
                    standaloneItems = []
                }

                // Extract header text (between ** and **)
                let startIdx = trimmed.index(trimmed.startIndex, offsetBy: 2)
                let headerText = String(trimmed[startIdx..<endRange.lowerBound])

                currentSection = GoalSection(title: headerText, items: [])
            }
            // Also support # headers
            else if trimmed.hasPrefix("#") {
                if let section = currentSection {
                    result.append(section)
                }
                if !standaloneItems.isEmpty && currentSection == nil {
                    result.append(GoalSection(title: "General", items: standaloneItems))
                    standaloneItems = []
                }

                var headerText = trimmed
                while headerText.hasPrefix("#") {
                    headerText = String(headerText.dropFirst())
                }
                headerText = headerText.trimmingCharacters(in: .whitespaces)

                currentSection = GoalSection(title: headerText, items: [])
            } else {
                // Content line - clean up prefixes
                var content = trimmed

                // Remove list markers
                if content.hasPrefix("- ") || content.hasPrefix("* ") {
                    content = String(content.dropFirst(2))
                } else if let match = content.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                    content = String(content[match.upperBound...])
                }

                content = content.trimmingCharacters(in: .whitespaces)

                if !content.isEmpty {
                    if currentSection != nil {
                        currentSection?.items.append(content)
                    } else {
                        standaloneItems.append(content)
                    }
                }
            }
        }

        // Don't forget the last section
        if let section = currentSection {
            result.append(section)
        }

        // Add standalone items if any remain
        if !standaloneItems.isEmpty {
            result.insert(GoalSection(title: "Focus", items: standaloneItems), at: 0)
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with title and edit button
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.accent)
                Text("Goals")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.text)

                Spacer()

                Button(action: {
                    if isEditing {
                        saveAndExitEdit()
                    } else {
                        editText = todoList.goals
                        withAnimation(Theme.Animation.quickFade) {
                            isEditing = true
                        }
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isEditing ? "checkmark" : "pencil")
                            .font(.system(size: 10, weight: .medium))
                        Text(isEditing ? "Done" : "Edit")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(isEditing ? .white : Theme.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isEditing ? Color.green : Theme.secondaryBackground)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .help(isEditing ? "Save changes" : "Edit goals")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.cardBackground)

            Divider()

            if isEditing {
                // Edit mode - Clean text editor
                TextEditor(text: $editText)
                    .font(.system(size: 13))
                    .lineSpacing(6)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .focused($isFocused)
                    .onAppear {
                        DispatchQueue.main.async {
                            editText = todoList.goals
                            isFocused = true
                        }
                    }
            } else {
                // View mode - Visual sections
                ScrollView {
                    if sections.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 32))
                                .foregroundColor(Theme.secondaryText.opacity(0.5))
                            Text("No goals yet")
                                .font(Theme.bodyFont)
                                .foregroundColor(Theme.secondaryText)
                            Text("Click Edit to add your goals")
                                .font(Theme.smallFont)
                                .foregroundColor(Theme.secondaryText.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 40)
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(sections) { section in
                                GoalSectionCard(section: section)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .background(Theme.cardBackground)
        .cornerRadius(Theme.cornerRadius)
        .animation(Theme.Animation.quickFade, value: isEditing)
    }

    private func saveAndExitEdit() {
        todoList.goals = editText
        todoList.saveTodos()
        withAnimation(Theme.Animation.quickFade) {
            isEditing = false
        }
    }
}

// Visual section card with header and bullet items
struct GoalSectionCard: View {
    let section: GoalSection
    @State private var isHovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(section.accentColor)
                    .frame(width: 4, height: 18)

                Text(section.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.text)
            }

            // Bullet items
            if !section.items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(section.items, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(section.accentColor.opacity(0.5))
                                .frame(width: 5, height: 5)
                                .padding(.top, 6)

                            GoalItemText(text: item)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusMd)
                .fill(Theme.cardBackground)
                .shadow(
                    color: isHovered ? Theme.Shadow.hoverColor : Theme.Shadow.cardColor,
                    radius: isHovered ? Theme.Shadow.hoverRadius : Theme.Shadow.cardRadius,
                    y: isHovered ? Theme.Shadow.hoverY : Theme.Shadow.cardY
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusMd)
                .stroke(section.accentColor.opacity(isHovered ? 0.25 : 0.1), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(Theme.Animation.microSpring, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// Helper view to render goal item text with bold colored tags inline
struct GoalItemText: View {
    let text: String

    var body: some View {
        buildText()
            .font(.system(size: 13))
            .foregroundColor(Theme.text.opacity(0.85))
    }

    private func buildText() -> Text {
        var result = Text("")
        let words = text.split(separator: " ", omittingEmptySubsequences: false)

        for (index, word) in words.enumerated() {
            let wordStr = String(word)
            let prefix = index > 0 ? " " : ""

            if wordStr.hasPrefix("#") && wordStr.count > 1 {
                let tagName = String(wordStr.dropFirst())
                result = result + Text(prefix) + Text("#\(tagName)")
                    .bold()
                    .foregroundColor(Theme.colorForTag(tagName))
            } else {
                result = result + Text(prefix + wordStr)
            }
        }

        return result
    }
}

// Live markdown preview for the editor
struct MarkdownPreview: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parseLines().enumerated()), id: \.offset) { _, line in
                lineView(for: line)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum LineType {
        case header(level: Int)
        case bullet
        case text
    }

    private struct ParsedLine {
        let type: LineType
        let content: String
    }

    private func parseLines() -> [ParsedLine] {
        text.components(separatedBy: .newlines).compactMap { line -> ParsedLine? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }

            // Check for headers
            if trimmed.hasPrefix("###") {
                return ParsedLine(type: .header(level: 3), content: String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("##") {
                return ParsedLine(type: .header(level: 2), content: String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            } else if trimmed.hasPrefix("#") && !trimmed.hasPrefix("# ") == false {
                return ParsedLine(type: .header(level: 1), content: String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces))
            }
            // Bullets
            else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                return ParsedLine(type: .bullet, content: String(trimmed.dropFirst(2)))
            }
            // Bold headers **text**
            else if trimmed.hasPrefix("**") {
                var content = String(trimmed.dropFirst(2))
                if let endIdx = content.range(of: "**") {
                    content = String(content[..<endIdx.lowerBound])
                }
                return ParsedLine(type: .header(level: 2), content: content)
            }

            return ParsedLine(type: .text, content: trimmed)
        }
    }

    @ViewBuilder
    private func lineView(for line: ParsedLine) -> some View {
        switch line.type {
        case .header(let level):
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.accent)
                    .frame(width: 3, height: level == 1 ? 16 : 14)
                renderContent(line.content)
                    .font(.system(size: level == 1 ? 14 : 12, weight: .semibold))
            }
            .padding(.top, 6)

        case .bullet:
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(Theme.accent.opacity(0.5))
                    .frame(width: 4, height: 4)
                    .padding(.top, 5)
                renderContent(line.content)
                    .font(.system(size: 11))
            }
            .padding(.leading, 8)

        case .text:
            renderContent(line.content)
                .font(.system(size: 11))
        }
    }

    @ViewBuilder
    private func renderContent(_ text: String) -> some View {
        // Simple text with #tag coloring
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        HStack(spacing: 4) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                let wordStr = String(word)
                if wordStr.hasPrefix("#") && wordStr.count > 1 {
                    let tagName = String(wordStr.dropFirst())
                    Text(wordStr)
                        .foregroundColor(Theme.colorForTag(tagName))
                        .fontWeight(.semibold)
                } else if wordStr.hasPrefix("**") && wordStr.hasSuffix("**") && wordStr.count > 4 {
                    let boldText = String(wordStr.dropFirst(2).dropLast(2))
                    Text(boldText)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.text)
                } else {
                    Text(wordStr)
                        .foregroundColor(Theme.text)
                }
            }
        }
    }
}

// Markdown renderer (read-only display)
struct MarkdownRenderer: View {
    let text: String

    private func processLines() -> [(isList: Bool, content: String, isNumbered: Bool, number: Int?, tags: [String])] {
        let lines = text.components(separatedBy: .newlines)
        var result: [(isList: Bool, content: String, isNumbered: Bool, number: Int?, tags: [String])] = []
        var currentListItems: [(content: String, tags: [String])] = []
        var currentNumberedItems: [(number: Int, content: String, tags: [String])] = []

        for line in lines {
            // Split content and tags
            let components = line.components(separatedBy: " #")
            let mainContent = components[0]
            let tags = components.dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }

            if mainContent.hasPrefix("- ") || mainContent.hasPrefix("* ") {
                let content = String(mainContent.dropFirst(2))
                currentListItems.append((content: content, tags: tags))
            } else if let match = mainContent.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                let number = Int(mainContent[..<match.upperBound].trimmingCharacters(in: CharacterSet(charactersIn: ". "))) ?? 0
                let content = String(mainContent[match.upperBound...]).trimmingCharacters(in: .whitespaces)
                currentNumberedItems.append((number: number, content: content, tags: tags))
            } else {
                if !currentListItems.isEmpty {
                    for item in currentListItems {
                        result.append((true, item.content, false, nil, item.tags))
                    }
                    currentListItems.removeAll()
                }
                if !currentNumberedItems.isEmpty {
                    for item in currentNumberedItems {
                        result.append((true, item.content, true, item.number, item.tags))
                    }
                    currentNumberedItems.removeAll()
                }
                if !mainContent.isEmpty {
                    result.append((false, mainContent, false, nil, tags))
                }
            }
        }

        if !currentListItems.isEmpty {
            for item in currentListItems {
                result.append((true, item.content, false, nil, item.tags))
            }
        }
        if !currentNumberedItems.isEmpty {
            for item in currentNumberedItems {
                result.append((true, item.content, true, item.number, item.tags))
            }
        }

        return result
    }

    private func renderContent() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let processedLines = processLines()

            ForEach(processedLines.indices, id: \.self) { index in
                let item = processedLines[index]

                if item.isList {
                    if item.isNumbered {
                        HStack(alignment: .top, spacing: 4) {
                            Text("\(item.number ?? 0).")
                                .foregroundColor(.secondary)
                                .frame(width: 25, alignment: .trailing)
                            HStack {
                                Text((try? AttributedString(markdown: item.content)) ?? AttributedString(item.content))
                                if !item.tags.isEmpty {
                                    ForEach(item.tags, id: \.self) { tag in
                                        TagPillView(tag: tag, size: .small)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        HStack(alignment: .top, spacing: 4) {
                            Text("•")
                                .foregroundColor(.secondary)
                            HStack {
                                Text((try? AttributedString(markdown: item.content)) ?? AttributedString(item.content))
                                if !item.tags.isEmpty {
                                    ForEach(item.tags, id: \.self) { tag in
                                        TagPillView(tag: tag, size: .small)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    HStack {
                        Text((try? AttributedString(markdown: item.content)) ?? AttributedString(item.content))
                        if !item.tags.isEmpty {
                            ForEach(item.tags, id: \.self) { tag in
                                TagPillView(tag: tag, size: .small)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(8)
    }

    var body: some View {
        ScrollView {
            renderContent()
        }
        .background(Theme.cardBackground)
        .cornerRadius(8)
    }
}
