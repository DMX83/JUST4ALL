import tempfile
from pathlib import Path
import unittest

import fitz

from just4pdf.services.pdf_to_images import export_pdf_to_images
from just4pdf.services.images_to_pdf import images_to_pdf
from just4pdf.services.pdf_tools import merge_pdfs, compress_pdf


class ServicesSmokeTest(unittest.TestCase):
    def test_pdf_to_images_and_back(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            pdf_path = tmp / "sample.pdf"

            doc = fitz.open()
            for i in range(3):
                page = doc.new_page()
                page.insert_text((72, 72), f"Hola {i + 1}")
            doc.save(str(pdf_path))
            doc.close()

            out_dir = tmp / "images"
            images = export_pdf_to_images(str(pdf_path), str(out_dir), zoom=1.0)
            self.assertEqual(len(images), 3)

            out_pdf = tmp / "merged.pdf"
            images_to_pdf(images, str(out_pdf))
            self.assertTrue(out_pdf.exists())

    def test_merge_and_compress(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            pdf1 = tmp / "a.pdf"
            pdf2 = tmp / "b.pdf"

            doc = fitz.open()
            doc.new_page()
            doc.save(str(pdf1))
            doc.close()

            doc = fitz.open()
            doc.new_page()
            doc.save(str(pdf2))
            doc.close()

            merged = tmp / "merged.pdf"
            merge_pdfs([str(pdf1), str(pdf2)], str(merged))
            self.assertTrue(merged.exists())

            compressed = tmp / "compressed.pdf"
            compress_pdf(str(merged), str(compressed), level="medium")
            self.assertTrue(compressed.exists())


if __name__ == "__main__":
    unittest.main()
