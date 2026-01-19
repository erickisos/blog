#!/usr/bin/env bb

(require '[babashka.fs :as fs]
         '[babashka.process :as p])

(defn installed?
  "Check if a given binary tool is installed"
  [tool]
  (try (p/shell {:out :string :err :string} "which" tool)
       (catch Exception _
         (println "❌ Error: Pandoc no està instalado.")
         false)))

(defn org->md
  [file output-dir]
  (let [filename (fs/file-name file)
        stem     (fs/strip-ext filename)
        md-file  (fs/file output-dir (str stem ".md"))]
    (println (str "🔄 Convirtiendo: " filename " - " (fs/file-name md-file)))
    (try (p/shell "pandoc"
                  (str file)
                  "-f" "org"
                  "-t" "gfm"
                  "--shift-heading-level-by=1"
                  "--wrap=preserve"
                  "--standalone"
                  "-o" (str md-file))
         (println (str "✅ Convertido exitosamente: " (fs/file-name md-file)))
         (catch Exception e
           (println (str "    ❌ Error al convertir " filename))
           (println (str "    " (.getMessage e)))))))

(defn parse-files
  "Call the org->md method for all the files in the input-dir"
  [input-dir output-dir]
  (if-let [org-files (fs/glob input-dir "*.org")]
    (do (println (str "Se han encontrado: " (count org-files) " archivos para convertir."))
        (run! #(org->md % output-dir) org-files))
    (println (str "⚠️ No se encontraron archivos .org en " input-dir))))

(defn main [& _args]
  (let [script-dir   (fs/parent *file*)
        project-root (fs/parent script-dir)
        input-dir    (fs/file project-root "articles")
        output-dir   (fs/file project-root "build")]
    (println (str "📁 Input directory: " input-dir))
    (println (str "📁 Output directory: " output-dir))
    (fs/create-dirs output-dir)
    (when (installed? "pandoc")
      (parse-files input-dir output-dir))))

(when (= *file* (System/getProperty "babashka.file"))
  (apply main *command-line-args*))
