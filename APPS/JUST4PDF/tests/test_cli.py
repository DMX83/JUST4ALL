import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import fitz

PY = sys.executable


def run_cli(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [PY, "-m", "just4pdf.cli", *args],
        capture_output=True,
        text=True,
    )


def make_pdf(path: Path, pages: int = 1) -> None:
    doc = fitz.open()
    for index in range(pages):
        page = doc.new_page()
        page.insert_text((72, 72), f"Pagina {index + 1}")
    doc.save(str(path))
    doc.close()


class CliSmokeTest(unittest.TestCase):
    def test_merge(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            a = tmp / "a.pdf"
            b = tmp / "b.pdf"
            out = tmp / "out.pdf"
            make_pdf(a, pages=1)
            make_pdf(b, pages=2)

            result = run_cli("merge", "-o", str(out), str(a), str(b))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(out.exists())
            doc = fitz.open(str(out))
            self.assertEqual(doc.page_count, 3)
            doc.close()

    def test_merge_usage_error(self) -> None:
        result = run_cli("merge", "solo-uno.pdf")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("al menos 2 PDFs", result.stderr)

    def test_pdf2img(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            source = tmp / "doc.pdf"
            out_dir = tmp / "imgs"
            make_pdf(source, pages=2)

            result = run_cli("pdf2img", "--zoom", "1.0", "--out-dir", str(out_dir), str(source))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(len(list(out_dir.glob("page-*.png"))), 2)

    def test_compress(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            source = tmp / "doc.pdf"
            out = tmp / "doc-comprimido.pdf"
            make_pdf(source, pages=3)

            result = run_cli("compress", "--level", "medium", "-o", str(out), str(source))
            self.assertEqual(result.returncode, 0, result.stderr)
            # Con safe=True puede no haber ganancia (PDF diminuto): ambas salidas son válidas.
            if out.exists():
                self.assertIn(str(out), result.stdout)
            else:
                self.assertIn("sin-ganancia", result.stdout)

    def test_img2pdf(self) -> None:
        from PIL import Image

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            image = tmp / "imagen.png"
            Image.new("RGB", (60, 40), (200, 30, 30)).save(str(image))
            out = tmp / "salida.pdf"

            result = run_cli("img2pdf", "-o", str(out), str(image))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(out.exists())


if __name__ == "__main__":
    unittest.main()
